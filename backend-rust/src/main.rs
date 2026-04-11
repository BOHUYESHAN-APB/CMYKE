use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_yaml::Value as YamlValue;
use std::io;
use std::{
    collections::{HashMap, VecDeque},
    net::SocketAddr,
    path::{Component, Path, PathBuf},
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tokio::{
    fs,
    io::{AsyncReadExt, AsyncWriteExt},
    time::{sleep, timeout},
};
use tokio::{process::Command, sync::Mutex};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use uuid::Uuid;

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: &'static str,
    service: &'static str,
    version: &'static str,
}

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        service: "cmyke-backend",
        version: env!("CARGO_PKG_VERSION"),
    })
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Pairing {
    id: String,
    token: String,
    mode: String,
    label: Option<String>,
    created_at: i64,
    expires_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PairingCreateRequest {
    mode: String,
    label: Option<String>,
    expires_in_sec: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PairingCreateResponse {
    pairing: Pairing,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PairingVerifyRequest {
    token: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PairingVerifyResponse {
    ok: bool,
    pairing: Option<Pairing>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct InboundMessage {
    channel: String,
    user_id: String,
    user_display: Option<String>,
    chat_id: String,
    text: String,
    media: Vec<String>,
    timestamp: i64,
    trace_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OutboundMessage {
    channel: String,
    chat_id: String,
    text: String,
    media: Vec<String>,
    reply_to: Option<String>,
    trace_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct InboundAck {
    accepted: bool,
    session_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeFileRef {
    path: String,
    label: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeRunRequest {
    pairing_token: Option<String>,
    trace_id: Option<String>,
    session_id: String,
    cancel_group: Option<String>,
    interruptible: Option<bool>,
    workspace: Option<String>,
    message: Option<String>,
    input: Option<serde_json::Value>,
    command: Option<String>,
    model: Option<String>,
    agent: Option<String>,
    files: Option<Vec<OpencodeFileRef>>,
    cwd: Option<String>,
    format: Option<String>,
    share: Option<bool>,
    attach: Option<String>,
    port: Option<u16>,
    #[serde(rename = "continue")]
    r#continue: Option<bool>,
    session: Option<String>,
    fork: Option<bool>,
    title: Option<String>,
    timeout_ms: Option<u64>,
    allowed_commands: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeRunResponse {
    ok: bool,
    exit_code: i32,
    stdout: String,
    stderr: String,
    format: String,
    events: Vec<serde_json::Value>,
    session_id: String,
    trace_id: Option<String>,
    files_written: Vec<String>,
    duration_ms: u128,
    workspace_root: String,
    log_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeCancelRequest {
    pairing_token: Option<String>,
    session_id: Option<String>,
    cancel_group: Option<String>,
    reason: Option<String>,
    ttl_sec: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeCancelResponse {
    ok: bool,
    accepted: bool,
    session_id: Option<String>,
    cancel_group: Option<String>,
    active_runs_signaled: usize,
    expires_at: i64,
    reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct GatewayInfoResponse {
    service: &'static str,
    version: &'static str,
    mode: &'static str,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct GatewayCapabilitiesResponse {
    ok: bool,
    service: &'static str,
    version: &'static str,
    routes: Vec<String>,
    features: Vec<String>,
    runtime: GatewayRuntimeSnapshot,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct GatewayRuntimeSnapshot {
    pairings_active: usize,
    sessions_mapped: usize,
    inbound_log_size: usize,
    outbound_log_size: usize,
    active_runs: usize,
    canceled_sessions: usize,
    canceled_groups: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ActiveRun {
    trace_id: String,
    session_id: String,
    cancel_group: Option<String>,
    interruptible: bool,
    started_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillsInstalledRequest {
    pairing_token: Option<String>,
    workspace: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillsInstalledResponse {
    ok: bool,
    skills: Vec<String>,
    items: Vec<OpencodeSkillCatalogItem>,
    opencode_root: String,
    config_path: String,
    config_dir: String,
    skill_dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillSourceInfo {
    #[serde(rename = "type")]
    kind: String,
    label: String,
    location: String,
    root: Option<String>,
    #[serde(rename = "ref")]
    r#ref: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct OpencodeSkillRequirements {
    bins: Vec<String>,
    env: Vec<String>,
    os: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillCatalogItem {
    name: String,
    display_name: String,
    description: Option<String>,
    author: Option<String>,
    version: Option<String>,
    homepage: Option<String>,
    tags: Vec<String>,
    user_invocable: Option<bool>,
    status: String,
    relative_path: Option<String>,
    manifest_path: Option<String>,
    installed_at: Option<i64>,
    has_frontmatter: bool,
    requirements: OpencodeSkillRequirements,
    source: Option<OpencodeSkillSourceInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillManifest {
    schema_version: u32,
    name: String,
    display_name: String,
    description: Option<String>,
    author: Option<String>,
    version: Option<String>,
    homepage: Option<String>,
    tags: Vec<String>,
    user_invocable: Option<bool>,
    relative_path: Option<String>,
    installed_at: i64,
    has_frontmatter: bool,
    requirements: OpencodeSkillRequirements,
    source: OpencodeSkillSourceInfo,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
enum OpencodeSkillSource {
    /// Clone a repo, then scan for SKILL.md under `root` (default: "skills").
    Git {
        url: String,
        #[serde(rename = "ref")]
        r#ref: Option<String>,
        root: Option<String>,
    },
    /// Scan a local directory for SKILL.md under `root` (default: ".").
    Local { path: String, root: Option<String> },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillsInstallRequest {
    pairing_token: Option<String>,
    workspace: Option<String>,
    source: OpencodeSkillSource,
    overwrite: Option<bool>,
    limit: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillNamedRequest {
    pairing_token: Option<String>,
    workspace: Option<String>,
    name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillsPreviewRequest {
    pairing_token: Option<String>,
    workspace: Option<String>,
    source: OpencodeSkillSource,
    overwrite: Option<bool>,
    limit: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillsPreviewResponse {
    ok: bool,
    items: Vec<OpencodeSkillCatalogItem>,
    errors: Vec<String>,
    skill_dir: String,
    total: usize,
    ready: usize,
    conflicts: usize,
    overwrites: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillsInstallResponse {
    ok: bool,
    installed: Vec<String>,
    skipped: Vec<String>,
    errors: Vec<String>,
    skill_dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillRemoveResponse {
    ok: bool,
    removed: bool,
    name: String,
    errors: Vec<String>,
    skill_dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillSyncPreviewResponse {
    ok: bool,
    name: String,
    action: String,
    current: OpencodeSkillCatalogItem,
    candidate: Option<OpencodeSkillCatalogItem>,
    errors: Vec<String>,
    skill_dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillSyncResponse {
    ok: bool,
    name: String,
    action: String,
    item: Option<OpencodeSkillCatalogItem>,
    errors: Vec<String>,
    skill_dir: String,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    ok: bool,
    error: String,
}

#[derive(Debug, Default)]
struct GatewayState {
    pairings: HashMap<String, Pairing>,
    sessions: HashMap<String, String>,
    inbound_log: VecDeque<InboundMessage>,
    outbound_log: VecDeque<OutboundMessage>,
    active_runs: HashMap<String, ActiveRun>,
    canceled_sessions: HashMap<String, i64>,
    canceled_groups: HashMap<String, i64>,
}

type SharedState = Arc<Mutex<GatewayState>>;

async fn pairing_create(
    State(state): State<SharedState>,
    Json(payload): Json<PairingCreateRequest>,
) -> Json<PairingCreateResponse> {
    let now = now_ts();
    let expires_in = payload.expires_in_sec.unwrap_or(600).max(60);
    let pairing = Pairing {
        id: Uuid::new_v4().to_string(),
        token: Uuid::new_v4().to_string(),
        mode: payload.mode,
        label: payload.label,
        created_at: now,
        expires_at: now + expires_in,
    };
    let mut guard = state.lock().await;
    guard.pairings.insert(pairing.id.clone(), pairing.clone());
    Json(PairingCreateResponse { pairing })
}

async fn pairing_verify(
    State(state): State<SharedState>,
    Json(payload): Json<PairingVerifyRequest>,
) -> Json<PairingVerifyResponse> {
    let mut guard = state.lock().await;
    cleanup_pairings(&mut guard);
    let pairing = guard
        .pairings
        .values()
        .find(|p| p.token == payload.token)
        .cloned();
    Json(PairingVerifyResponse {
        ok: pairing.is_some(),
        pairing,
    })
}

async fn pairing_list(State(state): State<SharedState>) -> Json<Vec<Pairing>> {
    let mut guard = state.lock().await;
    cleanup_pairings(&mut guard);
    let list = guard.pairings.values().cloned().collect::<Vec<_>>();
    Json(list)
}

async fn gateway_info() -> Json<GatewayInfoResponse> {
    Json(GatewayInfoResponse {
        service: "cmyke-backend",
        version: env!("CARGO_PKG_VERSION"),
        mode: "gateway",
    })
}

async fn gateway_capabilities(
    State(state): State<SharedState>,
) -> Json<GatewayCapabilitiesResponse> {
    let mut guard = state.lock().await;
    cleanup_pairings(&mut guard);
    cleanup_cancellations(&mut guard);
    Json(GatewayCapabilitiesResponse {
        ok: true,
        service: "cmyke-backend",
        version: env!("CARGO_PKG_VERSION"),
        routes: vec![
            "/api/v1/health".to_string(),
            "/api/v1/gateway/info".to_string(),
            "/api/v1/gateway/capabilities".to_string(),
            "/api/v1/gateway/pairing/create".to_string(),
            "/api/v1/gateway/pairing/verify".to_string(),
            "/api/v1/gateway/pairing/list".to_string(),
            "/api/v1/gateway/inbound".to_string(),
            "/api/v1/gateway/outbound".to_string(),
            "/api/v1/opencode/run".to_string(),
            "/api/v1/opencode/cancel".to_string(),
            "/api/v1/opencode/skills/installed".to_string(),
            "/api/v1/opencode/skills/preview".to_string(),
            "/api/v1/opencode/skills/install".to_string(),
            "/api/v1/opencode/skills/remove".to_string(),
            "/api/v1/opencode/skills/sync/preview".to_string(),
            "/api/v1/opencode/skills/sync".to_string(),
        ],
        features: vec![
            "pairing".to_string(),
            "opencode_run".to_string(),
            "opencode_cancel".to_string(),
            "skills_install".to_string(),
            "skills_preview".to_string(),
            "skills_catalog".to_string(),
            "skills_manifest".to_string(),
            "skills_remove".to_string(),
            "skills_sync".to_string(),
            "sandbox_workspace".to_string(),
            "event_trace_id".to_string(),
            "interruptible_run".to_string(),
        ],
        runtime: GatewayRuntimeSnapshot {
            pairings_active: guard.pairings.len(),
            sessions_mapped: guard.sessions.len(),
            inbound_log_size: guard.inbound_log.len(),
            outbound_log_size: guard.outbound_log.len(),
            active_runs: guard.active_runs.len(),
            canceled_sessions: guard.canceled_sessions.len(),
            canceled_groups: guard.canceled_groups.len(),
        },
    })
}

async fn opencode_cancel(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(payload): Json<OpencodeCancelRequest>,
) -> Result<Json<OpencodeCancelResponse>, (StatusCode, Json<ErrorResponse>)> {
    require_valid_pairing(&state, &headers, payload.pairing_token.as_deref()).await?;

    let session_id = payload
        .session_id
        .as_ref()
        .map(|raw| raw.trim().to_string())
        .filter(|raw| !raw.is_empty());
    if let Some(session) = session_id.as_deref() {
        if !is_safe_session_id(session) {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    ok: false,
                    error: "invalid session_id".to_string(),
                }),
            ));
        }
    }

    let cancel_group = normalize_cancel_group(payload.cancel_group.as_deref());
    if session_id.is_none() && cancel_group.is_none() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                ok: false,
                error: "session_id or cancel_group required".to_string(),
            }),
        ));
    }

    let now = now_ts();
    let ttl = payload.ttl_sec.unwrap_or(180).clamp(30, 3600);
    let expires_at = now + ttl;

    let mut guard = state.lock().await;
    cleanup_cancellations(&mut guard);

    if let Some(session) = session_id.as_ref() {
        guard
            .canceled_sessions
            .insert(session.to_string(), expires_at);
    }
    if let Some(group) = cancel_group.as_ref() {
        guard.canceled_groups.insert(group.to_string(), expires_at);
    }

    let active_runs_signaled = guard
        .active_runs
        .values()
        .filter(|run| {
            let session_match = session_id
                .as_ref()
                .map(|session| session == &run.session_id)
                .unwrap_or(false);
            let group_match = cancel_group
                .as_ref()
                .and_then(|group| {
                    run.cancel_group
                        .as_ref()
                        .map(|run_group| run_group == group)
                })
                .unwrap_or(false);
            (session_match || group_match) && run.interruptible
        })
        .count();

    Ok(Json(OpencodeCancelResponse {
        ok: true,
        accepted: true,
        session_id,
        cancel_group,
        active_runs_signaled,
        expires_at,
        reason: payload.reason,
    }))
}

async fn inbound_message(
    State(state): State<SharedState>,
    Json(mut payload): Json<InboundMessage>,
) -> Json<InboundAck> {
    if payload.trace_id.trim().is_empty() {
        payload.trace_id = Uuid::new_v4().to_string();
    }
    if payload.timestamp <= 0 {
        payload.timestamp = now_ts();
    }
    let mut guard = state.lock().await;
    let session_key = format!(
        "{}:{}:{}",
        payload.channel, payload.chat_id, payload.user_id
    );
    let session_id = guard
        .sessions
        .entry(session_key)
        .or_insert_with(|| Uuid::new_v4().to_string())
        .clone();
    guard.inbound_log.push_back(payload);
    trim_log(&mut guard.inbound_log, 200);
    Json(InboundAck {
        accepted: true,
        session_id,
    })
}

async fn outbound_message(
    State(state): State<SharedState>,
    Json(payload): Json<OutboundMessage>,
) -> Json<serde_json::Value> {
    let mut guard = state.lock().await;
    guard.outbound_log.push_back(payload);
    trim_log(&mut guard.outbound_log, 200);
    Json(serde_json::json!({ "accepted": true }))
}

async fn opencode_run(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(payload): Json<OpencodeRunRequest>,
) -> Result<Json<OpencodeRunResponse>, (StatusCode, Json<ErrorResponse>)> {
    let token = extract_pairing_token(&headers, &payload).ok_or_else(|| {
        (
            StatusCode::UNAUTHORIZED,
            Json(ErrorResponse {
                ok: false,
                error: "pairing token required".to_string(),
            }),
        )
    })?;

    let pairing_ok = {
        let mut guard = state.lock().await;
        cleanup_pairings(&mut guard);
        guard.pairings.values().any(|p| p.token == token)
    };
    if !pairing_ok {
        return Err((
            StatusCode::UNAUTHORIZED,
            Json(ErrorResponse {
                ok: false,
                error: "invalid or expired pairing token".to_string(),
            }),
        ));
    }

    let session_id = payload.session_id.trim();
    if session_id.is_empty() || !is_safe_session_id(session_id) {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                ok: false,
                error: "invalid session_id".to_string(),
            }),
        ));
    }

    let message = resolve_message(&payload).map_err(|err| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                ok: false,
                error: err,
            }),
        )
    })?;

    let format = normalize_format(payload.format.as_deref()).map_err(|err| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                ok: false,
                error: err,
            }),
        )
    })?;

    let timeout_ms = clamp_timeout_ms(payload.timeout_ms);
    let workspace_container = resolve_workspace_container_root(payload.workspace.as_deref())
        .map_err(|err| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let workspace_root = workspace_container.join(session_id);
    ensure_workspace_dirs(&workspace_root)
        .await
        .map_err(|err| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let trace_id = payload
        .trace_id
        .as_ref()
        .map(|raw| raw.trim().to_string())
        .filter(|raw| !raw.is_empty())
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    let cancel_group = normalize_cancel_group(payload.cancel_group.as_deref());
    let interruptible = payload.interruptible.unwrap_or(true);
    let trace_id_fs = sanitize_trace_id(&trace_id);
    let run_started_at = SystemTime::now()
        .checked_sub(Duration::from_secs(2))
        .unwrap_or_else(|| SystemTime::now());
    let opencode_log_path = workspace_root.join("logs").join("opencode_runs.jsonl");
    let opencode_artifact_dir = workspace_root.join("logs").join("opencode_runs");
    let _ = fs::create_dir_all(&opencode_artifact_dir).await;
    let opencode_artifact_path = opencode_artifact_dir.join(format!("{trace_id_fs}.json"));

    if interruptible && is_run_canceled(&state, session_id, cancel_group.as_deref()).await {
        let response = OpencodeRunResponse {
            ok: false,
            exit_code: -2,
            stdout: String::new(),
            stderr: "cancelled before start".to_string(),
            format: format.clone(),
            events: Vec::new(),
            session_id: session_id.to_string(),
            trace_id: Some(trace_id.clone()),
            files_written: Vec::new(),
            duration_ms: 0,
            workspace_root: workspace_root.to_string_lossy().to_string(),
            log_path: opencode_log_path.to_string_lossy().to_string(),
        };
        return Ok(Json(response));
    }

    if let Err(err) = append_jsonl_log(
        &opencode_log_path,
        serde_json::json!({
            "event": "opencode_run_start",
            "at": now_ts(),
            "trace_id": trace_id.as_str(),
            "session_id": session_id,
            "cancel_group": cancel_group,
            "interruptible": interruptible,
            "workspace": workspace_root.to_string_lossy(),
            "cwd": payload.cwd.as_deref().unwrap_or("scratch"),
            "format": format.as_str(),
            "command": payload.command.as_deref().unwrap_or(""),
        }),
    )
    .await
    {
        tracing::warn!("failed to write opencode start log: {}", err);
    }
    tracing::info!(
        trace_id = %trace_id,
        session_id = %session_id,
        workspace_root = %workspace_root.to_string_lossy(),
        log_path = %opencode_log_path.to_string_lossy(),
        "opencode run started"
    );

    let cwd_rel = payload.cwd.as_deref().unwrap_or("scratch");
    if !is_safe_rel_path(cwd_rel) {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                ok: false,
                error: "invalid cwd".to_string(),
            }),
        ));
    }
    let cwd = workspace_root.join(cwd_rel);
    if let Err(err) = fs::create_dir_all(&cwd).await {
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                ok: false,
                error: err.to_string(),
            }),
        ));
    }

    if let Err(err) = enforce_allowed_command(
        payload.command.as_deref(),
        payload.allowed_commands.as_ref(),
    ) {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                ok: false,
                error: err,
            }),
        ));
    }

    let mut cmd = Command::new(resolve_opencode_bin());
    cmd.arg("run");
    cmd.arg(&message);
    cmd.current_dir(&cwd);
    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());

    // Ensure a shared OpenCode config/skill store exists for this workspace container
    // so that skills are reusable across sessions while keeping per-session sandboxes.
    //
    // Layout:
    //   <workspace_container>/_shared/opencode/opencode.jsonc
    //   <workspace_container>/_shared/opencode/.opencode/skill/<skill>/SKILL.md
    let opencode_root = workspace_container.join("_shared").join("opencode");
    if let Ok((config_path, config_dir)) = ensure_opencode_project_config(&opencode_root).await {
        cmd.env("OPENCODE_CONFIG", config_path);
        cmd.env("OPENCODE_CONFIG_DIR", config_dir);
        cmd.env("OPENCODE_DISABLE_AUTOUPDATE", "true");
    }

    if let Some(command) = payload.command.as_deref() {
        cmd.arg("--command").arg(command);
    }
    if let Some(model) = payload.model.as_deref() {
        cmd.arg("--model").arg(model);
    }
    if let Some(agent) = payload.agent.as_deref() {
        cmd.arg("--agent").arg(agent);
    }
    if let Some(files) = payload.files.as_ref() {
        for file in files {
            let file_path = resolve_workspace_path(&workspace_root, &file.path).map_err(|err| {
                (
                    StatusCode::BAD_REQUEST,
                    Json(ErrorResponse {
                        ok: false,
                        error: err,
                    }),
                )
            })?;
            cmd.arg("--file").arg(file_path);
        }
    }
    cmd.arg("--format").arg(&format);
    if payload.share.unwrap_or(false) {
        cmd.arg("--share");
    }
    if let Some(attach) = payload.attach.as_deref() {
        cmd.arg("--attach").arg(attach);
    }
    if payload.r#continue.unwrap_or(false) {
        cmd.arg("--continue");
    }
    if let Some(session) = payload.session.as_deref() {
        cmd.arg("--session").arg(session);
    }
    if payload.fork.unwrap_or(false) {
        cmd.arg("--fork");
    }
    if let Some(title) = payload.title.as_deref() {
        cmd.arg("--title").arg(title);
    }
    if let Some(port) = payload.port {
        cmd.arg("--port").arg(port.to_string());
    }

    let start = Instant::now();
    let mut child = match cmd.spawn() {
        Ok(child) => child,
        Err(err) => {
            let mut response = OpencodeRunResponse {
                ok: false,
                exit_code: -1,
                stdout: String::new(),
                stderr: err.to_string(),
                format: format.clone(),
                events: Vec::new(),
                session_id: session_id.to_string(),
                trace_id: Some(trace_id.clone()),
                files_written: Vec::new(),
                duration_ms: start.elapsed().as_millis(),
                workspace_root: workspace_root.to_string_lossy().to_string(),
                log_path: opencode_log_path.to_string_lossy().to_string(),
            };
            if let Err(log_err) = append_jsonl_log(
                &opencode_log_path,
                serde_json::json!({
                    "event": "opencode_run_finish",
                    "at": now_ts(),
                    "trace_id": trace_id.as_str(),
                    "session_id": session_id,
                    "ok": response.ok,
                    "exit_code": response.exit_code,
                    "timed_out": false,
                    "duration_ms": response.duration_ms,
                    "stderr_preview": preview_text(&response.stderr, 300),
                }),
            )
            .await
            {
                tracing::warn!("failed to write opencode finish log: {}", log_err);
            }
            tracing::warn!(
                trace_id = %trace_id,
                session_id = %session_id,
                error = %response.stderr,
                "opencode run failed to spawn"
            );
            let mut files_written = Vec::new();
            if let Some(rel) = workspace_rel_path(&workspace_root, &opencode_log_path) {
                files_written.push(rel);
            }
            if let Some(rel) = workspace_rel_path(&workspace_root, &opencode_artifact_path) {
                files_written.push(rel);
            }
            files_written.sort();
            files_written.dedup();
            response.files_written = files_written;

            let artifact = build_opencode_run_artifact_json(
                &trace_id,
                session_id,
                cwd_rel,
                &format,
                timeout_ms,
                payload.command.as_deref(),
                payload.model.as_deref(),
                payload.agent.as_deref(),
                &message,
                false,
                &response,
            );
            if let Err(err) = write_pretty_json(&opencode_artifact_path, artifact).await {
                tracing::warn!("failed to write opencode artifact: {}", err);
            }
            return Ok(Json(response));
        }
    };

    {
        let mut guard = state.lock().await;
        guard.active_runs.insert(
            trace_id.clone(),
            ActiveRun {
                trace_id: trace_id.clone(),
                session_id: session_id.to_string(),
                cancel_group: cancel_group.clone(),
                interruptible,
                started_at: now_ts(),
            },
        );
    }

    let mut stdout_handle = None;
    if let Some(stdout) = child.stdout.take() {
        stdout_handle = Some(tokio::spawn(async move {
            let mut buf = Vec::new();
            let _ = tokio::io::BufReader::new(stdout)
                .read_to_end(&mut buf)
                .await;
            buf
        }));
    }
    let mut stderr_handle = None;
    if let Some(stderr) = child.stderr.take() {
        stderr_handle = Some(tokio::spawn(async move {
            let mut buf = Vec::new();
            let _ = tokio::io::BufReader::new(stderr)
                .read_to_end(&mut buf)
                .await;
            buf
        }));
    }

    let (status, timed_out, canceled) = wait_child_with_timeout_and_cancel(
        &mut child,
        timeout_ms,
        &state,
        session_id,
        cancel_group.as_deref(),
        interruptible,
    )
    .await;

    let stdout_bytes = match stdout_handle {
        Some(handle) => handle.await.unwrap_or_default(),
        None => Vec::new(),
    };
    let stderr_bytes = match stderr_handle {
        Some(handle) => handle.await.unwrap_or_default(),
        None => Vec::new(),
    };
    let stdout = String::from_utf8_lossy(&stdout_bytes).to_string();
    let stderr = if timed_out {
        let mut msg = String::from_utf8_lossy(&stderr_bytes).to_string();
        if !msg.is_empty() {
            msg.push_str("\n");
        }
        msg.push_str("timeout");
        msg
    } else if canceled {
        let mut msg = String::from_utf8_lossy(&stderr_bytes).to_string();
        if !msg.is_empty() {
            msg.push_str("\n");
        }
        msg.push_str("cancelled");
        msg
    } else {
        String::from_utf8_lossy(&stderr_bytes).to_string()
    };

    let exit_code = if canceled {
        -2
    } else {
        status.and_then(|status| status.code()).unwrap_or(-1)
    };
    let ok = !timed_out && !canceled && exit_code == 0;
    let events = if format == "json" {
        stdout
            .lines()
            .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
            .collect()
    } else {
        Vec::new()
    };

    let mut response = OpencodeRunResponse {
        ok,
        exit_code,
        stdout,
        stderr,
        format: format.clone(),
        events,
        session_id: session_id.to_string(),
        trace_id: Some(trace_id.clone()),
        files_written: Vec::new(),
        duration_ms: start.elapsed().as_millis(),
        workspace_root: workspace_root.to_string_lossy().to_string(),
        log_path: opencode_log_path.to_string_lossy().to_string(),
    };
    let mut files_written =
        collect_files_written_since(&workspace_root, &cwd, run_started_at, 2000).await;
    if let Some(rel) = workspace_rel_path(&workspace_root, &opencode_log_path) {
        files_written.push(rel);
    }
    if let Some(rel) = workspace_rel_path(&workspace_root, &opencode_artifact_path) {
        files_written.push(rel);
    }
    files_written.sort();
    files_written.dedup();
    response.files_written = files_written;

    let artifact = build_opencode_run_artifact_json(
        &trace_id,
        session_id,
        cwd_rel,
        &format,
        timeout_ms,
        payload.command.as_deref(),
        payload.model.as_deref(),
        payload.agent.as_deref(),
        &message,
        timed_out,
        &response,
    );
    if let Err(err) = write_pretty_json(&opencode_artifact_path, artifact).await {
        tracing::warn!("failed to write opencode artifact: {}", err);
    }
    if let Err(log_err) = append_jsonl_log(
        &opencode_log_path,
        serde_json::json!({
            "event": "opencode_run_finish",
            "at": now_ts(),
            "trace_id": trace_id.as_str(),
            "session_id": session_id,
            "ok": response.ok,
            "exit_code": response.exit_code,
            "timed_out": timed_out,
            "canceled": canceled,
            "duration_ms": response.duration_ms,
            "stderr_preview": preview_text(&response.stderr, 300),
        }),
    )
    .await
    {
        tracing::warn!("failed to write opencode finish log: {}", log_err);
    }
    tracing::info!(
        trace_id = %trace_id,
        session_id = %session_id,
        ok = response.ok,
        exit_code = response.exit_code,
        canceled = canceled,
        duration_ms = response.duration_ms,
        log_path = %response.log_path,
        "opencode run finished"
    );

    {
        let mut guard = state.lock().await;
        guard.active_runs.remove(&trace_id);
    }

    Ok(Json(response))
}

fn trim_log<T>(log: &mut VecDeque<T>, max: usize) {
    while log.len() > max {
        log.pop_front();
    }
}

fn extract_pairing_token(headers: &HeaderMap, payload: &OpencodeRunRequest) -> Option<String> {
    if let Some(token) = payload.pairing_token.as_ref() {
        let trimmed = token.trim();
        if !trimmed.is_empty() {
            return Some(trimmed.to_string());
        }
    }
    if let Some(value) = headers.get("x-pairing-token") {
        if let Ok(token) = value.to_str() {
            let trimmed = token.trim();
            if !trimmed.is_empty() {
                return Some(trimmed.to_string());
            }
        }
    }
    if let Some(value) = headers.get("authorization") {
        if let Ok(auth) = value.to_str() {
            let auth = auth.trim();
            if let Some(token) = auth.strip_prefix("Bearer ") {
                let trimmed = token.trim();
                if !trimmed.is_empty() {
                    return Some(trimmed.to_string());
                }
            }
        }
    }
    None
}

fn extract_pairing_token_raw(headers: &HeaderMap, payload_token: Option<&str>) -> Option<String> {
    if let Some(token) = payload_token {
        let trimmed = token.trim();
        if !trimmed.is_empty() {
            return Some(trimmed.to_string());
        }
    }
    if let Some(value) = headers.get("x-pairing-token") {
        if let Ok(token) = value.to_str() {
            let trimmed = token.trim();
            if !trimmed.is_empty() {
                return Some(trimmed.to_string());
            }
        }
    }
    if let Some(value) = headers.get("authorization") {
        if let Ok(auth) = value.to_str() {
            let auth = auth.trim();
            if let Some(token) = auth.strip_prefix("Bearer ") {
                let trimmed = token.trim();
                if !trimmed.is_empty() {
                    return Some(trimmed.to_string());
                }
            }
        }
    }
    None
}

fn is_safe_session_id(session_id: &str) -> bool {
    !session_id.is_empty()
        && session_id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

fn is_safe_rel_path(path: &str) -> bool {
    if path.trim().is_empty() {
        return false;
    }
    let path = Path::new(path);
    if path.is_absolute() {
        return false;
    }
    path.components()
        .all(|component| matches!(component, Component::Normal(_)))
}

fn resolve_message(payload: &OpencodeRunRequest) -> Result<String, String> {
    if let Some(message) = payload.message.as_ref() {
        let trimmed = message.trim();
        if !trimmed.is_empty() {
            return Ok(trimmed.to_string());
        }
    }
    if let Some(input) = payload.input.as_ref() {
        if let Some(text) = input.as_str() {
            let trimmed = text.trim();
            if trimmed.is_empty() {
                return Err("message or input required".to_string());
            }
            return Ok(trimmed.to_string());
        }
        return serde_json::to_string(input).map_err(|err| err.to_string());
    }
    Err("message or input required".to_string())
}

fn normalize_format(format: Option<&str>) -> Result<String, String> {
    let value = format.unwrap_or("json").trim();
    match value {
        "json" | "default" => Ok(value.to_string()),
        _ => Err("format must be json or default".to_string()),
    }
}

fn clamp_timeout_ms(timeout_ms: Option<u64>) -> u64 {
    let default_ms = 120_000;
    let max_ms = std::env::var("CMYKE_OPENCODE_TIMEOUT_MAX_MS")
        .ok()
        .and_then(|raw| raw.parse::<u64>().ok())
        .unwrap_or(300_000);
    let min_ms = 1_000;
    timeout_ms.unwrap_or(default_ms).clamp(min_ms, max_ms)
}

fn resolve_workspace_container_root(workspace: Option<&str>) -> Result<PathBuf, String> {
    let base_root =
        std::env::var("CMYKE_WORKSPACE_ROOT").unwrap_or_else(|_| "workspace".to_string());
    let mut root = PathBuf::from(base_root);
    if let Some(workspace) = workspace {
        let trimmed = workspace.trim();
        if trimmed.is_empty() {
            return Err("workspace cannot be empty".to_string());
        }
        if !is_safe_rel_path(trimmed) {
            return Err("invalid workspace".to_string());
        }
        root = root.join(trimmed);
    }
    Ok(root)
}

fn resolve_workspace_path(root: &Path, rel: &str) -> Result<PathBuf, String> {
    let trimmed = rel.trim();
    if trimmed.is_empty() {
        return Err("file path cannot be empty".to_string());
    }
    if !is_safe_rel_path(trimmed) {
        return Err("file path must be workspace-relative".to_string());
    }
    Ok(root.join(trimmed))
}

async fn ensure_workspace_dirs(root: &Path) -> Result<(), String> {
    let inputs = root.join("inputs");
    let scratch = root.join("scratch");
    let outputs = root.join("outputs");
    let logs = root.join("logs");
    fs::create_dir_all(&inputs)
        .await
        .map_err(|err| err.to_string())?;
    fs::create_dir_all(&scratch)
        .await
        .map_err(|err| err.to_string())?;
    fs::create_dir_all(&outputs)
        .await
        .map_err(|err| err.to_string())?;
    fs::create_dir_all(&logs)
        .await
        .map_err(|err| err.to_string())?;
    Ok(())
}

async fn append_jsonl_log(path: &Path, entry: serde_json::Value) -> Result<(), String> {
    let line = serde_json::to_string(&entry).map_err(|err| err.to_string())?;
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .await
        .map_err(|err| err.to_string())?;
    file.write_all(line.as_bytes())
        .await
        .map_err(|err| err.to_string())?;
    file.write_all(b"\n").await.map_err(|err| err.to_string())?;
    Ok(())
}

fn workspace_rel_path(workspace_root: &Path, path: &Path) -> Option<String> {
    let rel = path.strip_prefix(workspace_root).ok()?;
    Some(rel.to_string_lossy().replace('\\', "/"))
}

async fn write_pretty_json(path: &Path, value: serde_json::Value) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .await
            .map_err(|err| err.to_string())?;
    }
    let text = serde_json::to_string_pretty(&value).map_err(|err| err.to_string())?;
    fs::write(path, text).await.map_err(|err| err.to_string())?;
    Ok(())
}

async fn collect_files_written_since(
    workspace_root: &Path,
    dir: &Path,
    since: SystemTime,
    limit: usize,
) -> Vec<String> {
    let workspace_root = workspace_root.to_path_buf();
    let dir = dir.to_path_buf();
    let since = since;
    let limit = limit.max(1);
    tokio::task::spawn_blocking(move || {
        let mut out = Vec::new();
        let mut stack = vec![dir];
        while let Some(current) = stack.pop() {
            if out.len() >= limit {
                break;
            }
            let rd = match std::fs::read_dir(&current) {
                Ok(rd) => rd,
                Err(_) => continue,
            };
            for entry in rd.flatten() {
                if out.len() >= limit {
                    break;
                }
                let name = entry.file_name().to_string_lossy().to_string();
                if name == ".git" || name == "node_modules" || name == "target" {
                    continue;
                }
                let ty = match entry.file_type() {
                    Ok(ty) => ty,
                    Err(_) => continue,
                };
                let path = entry.path();
                if ty.is_dir() {
                    stack.push(path);
                    continue;
                }
                if !ty.is_file() {
                    continue;
                }
                if let Ok(meta) = entry.metadata() {
                    if let Ok(modified) = meta.modified() {
                        if modified < since {
                            continue;
                        }
                    }
                }
                if let Ok(rel) = path.strip_prefix(&workspace_root) {
                    out.push(rel.to_string_lossy().replace('\\', "/"));
                }
            }
        }
        out
    })
    .await
    .unwrap_or_default()
}

fn build_opencode_run_artifact_json(
    trace_id: &str,
    session_id: &str,
    cwd_rel: &str,
    format: &str,
    timeout_ms: u64,
    command: Option<&str>,
    model: Option<&str>,
    agent: Option<&str>,
    message: &str,
    timed_out: bool,
    response: &OpencodeRunResponse,
) -> serde_json::Value {
    serde_json::json!({
        "event": "opencode_run",
        "at": now_ts(),
        "trace_id": trace_id,
        "session_id": session_id,
        "cwd": cwd_rel,
        "format": format,
        "timeout_ms": timeout_ms,
        "command": command,
        "model": model,
        "agent": agent,
        "message": message,
        "timed_out": timed_out,
        "response": response,
    })
}

fn preview_text(text: &str, max_chars: usize) -> String {
    if max_chars == 0 || text.is_empty() {
        return String::new();
    }
    let char_count = text.chars().count();
    if char_count <= max_chars {
        return text.to_string();
    }
    let mut out = String::with_capacity(max_chars + 3);
    for (idx, ch) in text.chars().enumerate() {
        if idx >= max_chars {
            break;
        }
        out.push(ch);
    }
    out.push_str("...");
    out
}

fn enforce_allowed_command(
    command: Option<&str>,
    allowed_request: Option<&Vec<String>>,
) -> Result<(), String> {
    let allowed_env = std::env::var("CMYKE_OPENCODE_ALLOWED_COMMANDS")
        .ok()
        .and_then(|raw| {
            let values = raw
                .split(',')
                .map(|entry| entry.trim().to_string())
                .filter(|entry| !entry.is_empty())
                .collect::<Vec<_>>();
            if values.is_empty() {
                None
            } else {
                Some(values)
            }
        });

    if let Some(command) = command {
        if let Some(allowed_env) = allowed_env.as_ref() {
            if !allowed_env.iter().any(|entry| entry == command) {
                return Err("command not allowed by server policy".to_string());
            }
        }
        if let Some(allowed_request) = allowed_request {
            if !allowed_request.is_empty() && !allowed_request.iter().any(|entry| entry == command)
            {
                return Err("command not in allowed_commands".to_string());
            }
        }
    } else if let Some(allowed_request) = allowed_request {
        if !allowed_request.is_empty() {
            return Err("command required when allowed_commands is provided".to_string());
        }
    }

    Ok(())
}

fn cleanup_pairings(state: &mut GatewayState) {
    let now = now_ts();
    state.pairings.retain(|_, p| p.expires_at > now);
}

fn normalize_cancel_group(raw: Option<&str>) -> Option<String> {
    raw.map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn cleanup_cancellations(state: &mut GatewayState) {
    let now = now_ts();
    state
        .canceled_sessions
        .retain(|_, expires_at| *expires_at > now);
    state
        .canceled_groups
        .retain(|_, expires_at| *expires_at > now);
}

fn is_session_or_group_canceled(
    state: &GatewayState,
    session_id: &str,
    cancel_group: Option<&str>,
) -> bool {
    if state.canceled_sessions.contains_key(session_id) {
        return true;
    }
    if let Some(group) = cancel_group {
        return state.canceled_groups.contains_key(group);
    }
    false
}

async fn is_run_canceled(
    state: &SharedState,
    session_id: &str,
    cancel_group: Option<&str>,
) -> bool {
    let mut guard = state.lock().await;
    cleanup_cancellations(&mut guard);
    is_session_or_group_canceled(&guard, session_id, cancel_group)
}

async fn wait_child_with_timeout_and_cancel(
    child: &mut tokio::process::Child,
    timeout_ms: u64,
    state: &SharedState,
    session_id: &str,
    cancel_group: Option<&str>,
    interruptible: bool,
) -> (Option<std::process::ExitStatus>, bool, bool) {
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return (Some(status), false, false),
            Ok(None) => {}
            Err(_) => return (None, false, false),
        }

        if interruptible && is_run_canceled(state, session_id, cancel_group).await {
            let _ = child.kill().await;
            let _ = child.wait().await;
            return (None, false, true);
        }

        if Instant::now() >= deadline {
            let _ = child.kill().await;
            let _ = child.wait().await;
            return (None, true, false);
        }

        sleep(Duration::from_millis(120)).await;
    }
}

fn now_ts() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::from_secs(0))
        .as_secs() as i64
}

fn resolve_listen_addr() -> SocketAddr {
    let host = std::env::var("CMYKE_BACKEND_HOST").unwrap_or_else(|_| "127.0.0.1".to_string());
    let port = std::env::var("CMYKE_BACKEND_PORT")
        .ok()
        .and_then(|raw| raw.parse::<u16>().ok())
        .unwrap_or(4891);
    format!("{host}:{port}")
        .parse()
        .unwrap_or_else(|_| SocketAddr::from(([127, 0, 0, 1], 4891)))
}

fn resolve_opencode_bin() -> PathBuf {
    if let Ok(raw) = std::env::var("CMYKE_OPENCODE_BIN") {
        let trimmed = raw.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed);
        }
    }

    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            let candidates: Vec<PathBuf> = if cfg!(windows) {
                vec![
                    dir.join("opencode.exe"),
                    dir.join("opencode"),
                    dir.join("tools").join("opencode.exe"),
                ]
            } else {
                vec![dir.join("opencode"), dir.join("tools").join("opencode")]
            };
            for path in candidates {
                if path.is_file() {
                    return path;
                }
            }
        }
    }

    PathBuf::from("opencode")
}

async fn ensure_opencode_project_config(
    opencode_root: &Path,
) -> Result<(PathBuf, PathBuf), String> {
    let config_path = opencode_root.join("opencode.jsonc");
    let config_dir = opencode_root.join(".opencode");
    let skill_dir = config_dir.join("skill");

    if let Err(err) = fs::create_dir_all(&skill_dir).await {
        return Err(err.to_string());
    }

    // Only seed files if they don't exist, so the user/agent can edit freely.
    if fs::metadata(&config_path).await.is_err() {
        let seed = r#"{
  // OpenCode project config (seeded by CMYKE gateway).
  // Edit this file to control OpenCode behavior for this workspace (shared config/skills).
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false
}
"#;
        if let Err(err) = fs::write(&config_path, seed).await {
            return Err(err.to_string());
        }
    }

    let skill_cmyke_policy = skill_dir.join("cmyke_policy").join("SKILL.md");
    if fs::metadata(&skill_cmyke_policy).await.is_err() {
        if let Some(parent) = skill_cmyke_policy.parent() {
            let _ = fs::create_dir_all(parent).await;
        }
        let seed = r#"# CMYKE Policy

You are running inside CMYKE's OpenCode tool gateway.

Hard rules:
- Do not output `[SPLIT]`.
- Do not use Markdown code fences (no ```).
- Prefer verifiable sources and include URLs when you cite facts.
- Only read/write files inside the current session workspace.

If you need to change OpenCode behavior, edit `opencode.jsonc` or files under `.opencode/` (stored under `workspace/_shared/opencode/`).
"#;
        let _ = fs::write(&skill_cmyke_policy, seed).await;
    }

    let skill_web_research = skill_dir.join("cmyke_web_research").join("SKILL.md");
    if fs::metadata(&skill_web_research).await.is_err() {
        if let Some(parent) = skill_web_research.parent() {
            let _ = fs::create_dir_all(parent).await;
        }
        let seed = r#"# CMYKE Web Research

When asked to research a topic:
1) Run multiple complementary web searches (official docs, reputable media, comparison, and academic/papers if relevant).
2) Extract key facts and list sources with URL + title + date if available.
3) Mark anything you cannot verify as \"unverified\".
4) Keep the output plain text (no Markdown code fences).
"#;
        let _ = fs::write(&skill_web_research, seed).await;
    }

    Ok((config_path, config_dir))
}

async fn require_valid_pairing(
    state: &SharedState,
    headers: &HeaderMap,
    payload_token: Option<&str>,
) -> Result<(), (StatusCode, Json<ErrorResponse>)> {
    let token = extract_pairing_token_raw(headers, payload_token).ok_or_else(|| {
        (
            StatusCode::UNAUTHORIZED,
            Json(ErrorResponse {
                ok: false,
                error: "pairing token required".to_string(),
            }),
        )
    })?;

    let pairing_ok = {
        let mut guard = state.lock().await;
        cleanup_pairings(&mut guard);
        guard.pairings.values().any(|p| p.token == token)
    };
    if !pairing_ok {
        return Err((
            StatusCode::UNAUTHORIZED,
            Json(ErrorResponse {
                ok: false,
                error: "invalid or expired pairing token".to_string(),
            }),
        ));
    }
    Ok(())
}

const CMYKE_SKILL_MANIFEST_NAME: &str = ".cmyke-skill.json";

#[derive(Debug, Clone, Default)]
struct ParsedSkillDoc {
    display_name: String,
    description: Option<String>,
    author: Option<String>,
    version: Option<String>,
    homepage: Option<String>,
    tags: Vec<String>,
    user_invocable: Option<bool>,
    has_frontmatter: bool,
    requirements: OpencodeSkillRequirements,
}

#[derive(Debug, Clone)]
struct DiscoveredSkill {
    source_dir: PathBuf,
    item: OpencodeSkillCatalogItem,
}

#[derive(Debug, Clone)]
struct SkillSyncCandidate {
    current: OpencodeSkillCatalogItem,
    candidate: Option<DiscoveredSkill>,
    errors: Vec<String>,
    action: String,
}

#[derive(Debug, Default)]
struct SkillDiscoveryResult {
    items: Vec<DiscoveredSkill>,
    errors: Vec<String>,
    cleanup_dir: Option<PathBuf>,
}

fn normalize_string_list(values: Vec<String>) -> Vec<String> {
    let mut out = Vec::new();
    for value in values {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            continue;
        }
        let normalized = trimmed.to_string();
        if !out.contains(&normalized) {
            out.push(normalized);
        }
    }
    out
}

fn split_markdown_frontmatter(markdown: &str) -> (Option<String>, String) {
    let normalized = markdown.replace("\r\n", "\n");
    let lines = normalized.lines().collect::<Vec<_>>();
    if lines.first().copied() != Some("---") {
        return (None, normalized);
    }

    let mut yaml_lines = Vec::new();
    let mut body_start = None;
    for (index, line) in lines.iter().enumerate().skip(1) {
        if *line == "---" || *line == "..." {
            body_start = Some(index + 1);
            break;
        }
        yaml_lines.push(*line);
    }

    if let Some(start) = body_start {
        return (
            Some(yaml_lines.join("\n")),
            lines[start..].join("\n").trim().to_string(),
        );
    }

    (None, normalized)
}

fn yaml_lookup<'a>(value: &'a YamlValue, path: &[&str]) -> Option<&'a YamlValue> {
    let mut current = value;
    for key in path {
        let map = current.as_mapping()?;
        current = map.get(&YamlValue::String((*key).to_string()))?;
    }
    Some(current)
}

fn yaml_scalar_to_string(value: &YamlValue) -> Option<String> {
    match value {
        YamlValue::String(raw) => {
            let trimmed = raw.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        }
        YamlValue::Number(raw) => Some(raw.to_string()),
        YamlValue::Bool(raw) => Some(raw.to_string()),
        _ => None,
    }
}

fn yaml_bool(value: &YamlValue) -> Option<bool> {
    match value {
        YamlValue::Bool(raw) => Some(*raw),
        YamlValue::String(raw) => match raw.trim().to_ascii_lowercase().as_str() {
            "true" => Some(true),
            "false" => Some(false),
            _ => None,
        },
        _ => None,
    }
}

fn yaml_string_list(value: &YamlValue) -> Vec<String> {
    match value {
        YamlValue::Sequence(items) => normalize_string_list(
            items
                .iter()
                .filter_map(yaml_scalar_to_string)
                .collect::<Vec<_>>(),
        ),
        YamlValue::String(raw) => normalize_string_list(
            raw.split(',')
                .map(|entry| entry.trim().to_string())
                .collect::<Vec<_>>(),
        ),
        _ => Vec::new(),
    }
}

fn parse_skill_requirements(frontmatter: Option<&YamlValue>) -> OpencodeSkillRequirements {
    let Some(frontmatter) = frontmatter else {
        return OpencodeSkillRequirements::default();
    };
    let requires = yaml_lookup(frontmatter, &["metadata", "openclaw", "requires"]);
    OpencodeSkillRequirements {
        bins: requires
            .and_then(|node| yaml_lookup(node, &["bins"]))
            .map(yaml_string_list)
            .unwrap_or_default(),
        env: requires
            .and_then(|node| yaml_lookup(node, &["env"]))
            .map(yaml_string_list)
            .unwrap_or_default(),
        os: requires
            .and_then(|node| yaml_lookup(node, &["os"]))
            .map(yaml_string_list)
            .unwrap_or_default(),
    }
}

fn markdown_title(body: &str) -> Option<String> {
    for line in body.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('#') {
            let title = trimmed.trim_start_matches('#').trim();
            if !title.is_empty() {
                return Some(title.to_string());
            }
        }
    }
    None
}

fn markdown_paragraph_summary(body: &str) -> Option<String> {
    let mut in_code = false;
    let mut paragraph = Vec::new();
    for line in body.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("```") {
            in_code = !in_code;
            continue;
        }
        if in_code {
            continue;
        }
        if trimmed.is_empty() {
            if !paragraph.is_empty() {
                break;
            }
            continue;
        }
        if trimmed.starts_with('#')
            || trimmed.starts_with('>')
            || trimmed.starts_with("- ")
            || trimmed.starts_with("* ")
            || trimmed.starts_with("| ")
            || trimmed.starts_with("<!--")
        {
            if paragraph.is_empty() {
                continue;
            }
            break;
        }
        if let Some(first) = trimmed.chars().next() {
            if first.is_ascii_digit() && trimmed.contains('.') && paragraph.is_empty() {
                continue;
            }
        }
        paragraph.push(trimmed.to_string());
    }
    if paragraph.is_empty() {
        None
    } else {
        Some(paragraph.join(" "))
    }
}

fn infer_author_from_relative_path(relative_path: Option<&str>) -> Option<String> {
    let raw = relative_path?;
    let parts = Path::new(raw)
        .components()
        .filter_map(|component| match component {
            Component::Normal(segment) => segment.to_str(),
            _ => None,
        })
        .collect::<Vec<_>>();
    if parts.len() >= 2 && parts[0].eq_ignore_ascii_case("skills") {
        return Some(parts[1].to_string());
    }
    None
}

fn infer_author_from_name(name: &str) -> Option<String> {
    name.split("__")
        .next()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn parse_skill_doc(
    markdown: &str,
    default_display_name: &str,
    relative_path: Option<&str>,
) -> ParsedSkillDoc {
    let (frontmatter_raw, body) = split_markdown_frontmatter(markdown);
    let frontmatter = frontmatter_raw
        .as_deref()
        .and_then(|raw| serde_yaml::from_str::<YamlValue>(raw).ok());
    let display_name = frontmatter
        .as_ref()
        .and_then(|doc| yaml_lookup(doc, &["name"]).and_then(yaml_scalar_to_string))
        .or_else(|| markdown_title(&body))
        .unwrap_or_else(|| default_display_name.to_string());
    let description = frontmatter
        .as_ref()
        .and_then(|doc| yaml_lookup(doc, &["description"]).and_then(yaml_scalar_to_string))
        .or_else(|| markdown_paragraph_summary(&body));
    let author = frontmatter
        .as_ref()
        .and_then(|doc| yaml_lookup(doc, &["author"]).and_then(yaml_scalar_to_string))
        .or_else(|| infer_author_from_relative_path(relative_path));
    let version = frontmatter
        .as_ref()
        .and_then(|doc| yaml_lookup(doc, &["version"]).and_then(yaml_scalar_to_string));
    let homepage = frontmatter
        .as_ref()
        .and_then(|doc| yaml_lookup(doc, &["homepage"]).and_then(yaml_scalar_to_string));
    let tags = frontmatter
        .as_ref()
        .and_then(|doc| yaml_lookup(doc, &["tags"]))
        .map(yaml_string_list)
        .unwrap_or_default();
    let user_invocable = frontmatter.as_ref().and_then(|doc| {
        yaml_lookup(doc, &["user-invocable"])
            .or_else(|| yaml_lookup(doc, &["user_invocable"]))
            .and_then(yaml_bool)
    });
    ParsedSkillDoc {
        display_name,
        description,
        author,
        version,
        homepage,
        tags,
        user_invocable,
        has_frontmatter: frontmatter_raw.is_some(),
        requirements: parse_skill_requirements(frontmatter.as_ref()),
    }
}

fn find_skill_markdown_path(dir: &Path) -> Option<PathBuf> {
    let upper = dir.join("SKILL.md");
    if upper.is_file() {
        return Some(upper);
    }
    let lower = dir.join("skill.md");
    if lower.is_file() {
        return Some(lower);
    }
    None
}

fn skill_manifest_path(skill_root: &Path) -> PathBuf {
    skill_root.join(CMYKE_SKILL_MANIFEST_NAME)
}

fn build_skill_manifest(
    item: &OpencodeSkillCatalogItem,
    installed_at: i64,
) -> Option<OpencodeSkillManifest> {
    let source = item.source.clone()?;
    Some(OpencodeSkillManifest {
        schema_version: 1,
        name: item.name.clone(),
        display_name: item.display_name.clone(),
        description: item.description.clone(),
        author: item.author.clone(),
        version: item.version.clone(),
        homepage: item.homepage.clone(),
        tags: item.tags.clone(),
        user_invocable: item.user_invocable,
        relative_path: item.relative_path.clone(),
        installed_at,
        has_frontmatter: item.has_frontmatter,
        requirements: item.requirements.clone(),
        source,
    })
}

fn catalog_item_from_manifest(
    manifest: OpencodeSkillManifest,
    manifest_path: &Path,
) -> OpencodeSkillCatalogItem {
    OpencodeSkillCatalogItem {
        name: manifest.name,
        display_name: manifest.display_name,
        description: manifest.description,
        author: manifest.author,
        version: manifest.version,
        homepage: manifest.homepage,
        tags: manifest.tags,
        user_invocable: manifest.user_invocable,
        status: "installed".to_string(),
        relative_path: manifest.relative_path,
        manifest_path: Some(manifest_path.to_string_lossy().to_string()),
        installed_at: Some(manifest.installed_at),
        has_frontmatter: manifest.has_frontmatter,
        requirements: manifest.requirements,
        source: Some(manifest.source),
    }
}

async fn read_installed_skill_item(skill_root: &Path) -> OpencodeSkillCatalogItem {
    let name = skill_root
        .file_name()
        .and_then(|segment| segment.to_str())
        .unwrap_or("skill")
        .to_string();
    let manifest_path = skill_manifest_path(skill_root);
    if let Ok(raw) = fs::read_to_string(&manifest_path).await {
        if let Ok(manifest) = serde_json::from_str::<OpencodeSkillManifest>(&raw) {
            return catalog_item_from_manifest(manifest, &manifest_path);
        }
    }

    let mut parsed = ParsedSkillDoc {
        display_name: name.clone(),
        author: infer_author_from_name(&name),
        ..ParsedSkillDoc::default()
    };
    if let Some(skill_md_path) = find_skill_markdown_path(skill_root) {
        if let Ok(markdown) = fs::read_to_string(skill_md_path).await {
            parsed = parse_skill_doc(&markdown, &name, None);
            if parsed.author.is_none() {
                parsed.author = infer_author_from_name(&name);
            }
        }
    }

    OpencodeSkillCatalogItem {
        name,
        display_name: parsed.display_name,
        description: parsed.description,
        author: parsed.author,
        version: parsed.version,
        homepage: parsed.homepage,
        tags: parsed.tags,
        user_invocable: parsed.user_invocable,
        status: "installed".to_string(),
        relative_path: None,
        manifest_path: if manifest_path.exists() {
            Some(manifest_path.to_string_lossy().to_string())
        } else {
            None
        },
        installed_at: None,
        has_frontmatter: parsed.has_frontmatter,
        requirements: parsed.requirements,
        source: None,
    }
}

fn build_discovered_skill(
    base_root: &Path,
    skill_root: &Path,
    source: &OpencodeSkillSourceInfo,
    installed_skill_dir: &Path,
    overwrite: bool,
) -> Result<DiscoveredSkill, String> {
    let name = derive_skill_name(base_root, skill_root);
    let relative_path = skill_root
        .strip_prefix(base_root)
        .ok()
        .map(|path| path.to_string_lossy().replace('\\', "/"));
    let default_display_name = skill_root
        .file_name()
        .and_then(|segment| segment.to_str())
        .filter(|segment| !segment.trim().is_empty())
        .unwrap_or(name.as_str())
        .to_string();
    let skill_md_path = find_skill_markdown_path(skill_root)
        .ok_or_else(|| format!("missing SKILL.md under {}", skill_root.to_string_lossy()))?;
    let markdown = std::fs::read_to_string(&skill_md_path).map_err(|err| err.to_string())?;
    let mut parsed = parse_skill_doc(&markdown, &default_display_name, relative_path.as_deref());
    if parsed.author.is_none() {
        parsed.author = infer_author_from_relative_path(relative_path.as_deref())
            .or_else(|| infer_author_from_name(&name));
    }
    let dest_exists = installed_skill_dir.join(&name).exists();
    let status = if dest_exists {
        if overwrite {
            "will_overwrite"
        } else {
            "conflict"
        }
    } else {
        "ready"
    };

    Ok(DiscoveredSkill {
        source_dir: skill_root.to_path_buf(),
        item: OpencodeSkillCatalogItem {
            name,
            display_name: parsed.display_name,
            description: parsed.description,
            author: parsed.author,
            version: parsed.version,
            homepage: parsed.homepage,
            tags: parsed.tags,
            user_invocable: parsed.user_invocable,
            status: status.to_string(),
            relative_path,
            manifest_path: None,
            installed_at: None,
            has_frontmatter: parsed.has_frontmatter,
            requirements: parsed.requirements,
            source: Some(source.clone()),
        },
    })
}

fn collect_discovered_skills(
    base_root: &Path,
    dirs: Vec<PathBuf>,
    source: &OpencodeSkillSourceInfo,
    installed_skill_dir: &Path,
    overwrite: bool,
) -> Result<Vec<DiscoveredSkill>, String> {
    let mut items = Vec::new();
    for dir in dirs {
        items.push(build_discovered_skill(
            base_root,
            &dir,
            source,
            installed_skill_dir,
            overwrite,
        )?);
    }
    Ok(items)
}

fn sanitize_skill_name(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    for c in raw.chars() {
        if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
            out.push(c);
        } else {
            out.push('_');
        }
    }
    let trimmed = out.trim_matches('_').to_string();
    if trimmed.is_empty() {
        "skill".to_string()
    } else {
        trimmed
    }
}

fn sanitize_trace_id(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return "trace".to_string();
    }
    let mut out = String::with_capacity(trimmed.len());
    for c in trimmed.chars() {
        if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
            out.push(c);
        } else {
            out.push('_');
        }
    }
    let cleaned = out.trim_matches('_').to_string();
    if cleaned.is_empty() {
        "trace".to_string()
    } else {
        cleaned
    }
}

fn parse_github_owner_repo(url: &str) -> Option<(String, String)> {
    let mut s = url.trim();
    if s.is_empty() {
        return None;
    }
    while s.ends_with('/') {
        s = &s[..s.len() - 1];
    }
    if let Some(stripped) = s.strip_suffix(".git") {
        s = stripped;
    }
    let idx = s.find("github.com")?;
    let mut tail = &s[idx + "github.com".len()..];
    // Handles formats:
    // - https://github.com/owner/repo
    // - git@github.com:owner/repo
    tail = tail.trim_start_matches(['/', ':']);
    let tail = tail.replace(':', "/");
    let mut parts = tail
        .split('/')
        .map(|p| p.trim())
        .filter(|p| !p.is_empty())
        .take(2);
    let owner = parts.next()?.to_string();
    let repo = parts.next()?.to_string();
    Some((owner, repo))
}

fn derive_skill_name(repo_root: &Path, skill_dir: &Path) -> String {
    if let Ok(rel) = skill_dir.strip_prefix(repo_root) {
        let parts = rel
            .components()
            .filter_map(|c| match c {
                Component::Normal(s) => s.to_str(),
                _ => None,
            })
            .collect::<Vec<_>>();
        if parts.len() >= 3 && parts[0].eq_ignore_ascii_case("skills") {
            return sanitize_skill_name(&parts[1..].join("__"));
        }
    }
    skill_dir
        .file_name()
        .and_then(|s| s.to_str())
        .map(sanitize_skill_name)
        .unwrap_or_else(|| "skill".to_string())
}

fn contains_skill_md(dir: &Path) -> bool {
    if dir.join("SKILL.md").is_file() {
        return true;
    }
    dir.join("skill.md").is_file()
}

fn collect_skill_dirs(root: &Path, limit: usize) -> Result<Vec<PathBuf>, String> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        if contains_skill_md(&dir) {
            out.push(dir.clone());
            if out.len() >= limit {
                break;
            }
            continue;
        }
        let read_dir = std::fs::read_dir(&dir).map_err(|e| e.to_string())?;
        for entry in read_dir.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if let Some(name) = path.file_name().and_then(|s| s.to_str()) {
                    if name == ".git" || name == "node_modules" || name == "target" {
                        continue;
                    }
                }
                stack.push(path);
            }
        }
    }
    Ok(out)
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> io::Result<()> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let path = entry.path();
        let file_name = entry.file_name();
        let name = file_name.to_string_lossy();
        if name == ".git" || name == "node_modules" || name == "target" {
            continue;
        }
        let dst_path = dst.join(file_name);
        let ty = entry.file_type()?;
        if ty.is_dir() {
            copy_dir_recursive(&path, &dst_path)?;
        } else if ty.is_file() {
            if let Some(parent) = dst_path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::copy(&path, &dst_path)?;
        }
    }
    Ok(())
}

fn build_local_source_info(base: &Path, root: Option<&str>) -> OpencodeSkillSourceInfo {
    let label = base
        .file_name()
        .and_then(|segment| segment.to_str())
        .filter(|segment| !segment.trim().is_empty())
        .unwrap_or("local")
        .to_string();
    OpencodeSkillSourceInfo {
        kind: "local".to_string(),
        label,
        location: base.to_string_lossy().to_string(),
        root: root
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
        r#ref: None,
    }
}

fn build_git_source_info(url: &str, git_ref: Option<&str>, root: &str) -> OpencodeSkillSourceInfo {
    let label = parse_github_owner_repo(url)
        .map(|(owner, repo)| format!("{owner}/{repo}"))
        .unwrap_or_else(|| url.to_string());
    OpencodeSkillSourceInfo {
        kind: "git".to_string(),
        label,
        location: url.to_string(),
        root: Some(root.to_string()),
        r#ref: git_ref.map(|value| value.to_string()),
    }
}

async fn write_skill_manifest(
    skill_root: &Path,
    item: &OpencodeSkillCatalogItem,
) -> Result<(), String> {
    let manifest =
        build_skill_manifest(item, now_ts()).ok_or_else(|| "missing skill source".to_string())?;
    let data = serde_json::to_vec_pretty(&manifest).map_err(|err| err.to_string())?;
    fs::write(skill_manifest_path(skill_root), data)
        .await
        .map_err(|err| err.to_string())
}

fn count_skill_items_with_status(items: &[OpencodeSkillCatalogItem], expected: &str) -> usize {
    items.iter().filter(|item| item.status == expected).count()
}

fn source_info_to_skill_source(
    source: &OpencodeSkillSourceInfo,
) -> Result<OpencodeSkillSource, String> {
    match source.kind.trim() {
        "git" => Ok(OpencodeSkillSource::Git {
            url: source.location.clone(),
            r#ref: source.r#ref.clone(),
            root: source.root.clone(),
        }),
        "local" => Ok(OpencodeSkillSource::Local {
            path: source.location.clone(),
            root: source.root.clone(),
        }),
        other => Err(format!("unsupported skill source type: {other}")),
    }
}

async fn resolve_installed_skill_item(
    skill_dir: &Path,
    name: &str,
) -> Result<OpencodeSkillCatalogItem, String> {
    let normalized = name.trim();
    if normalized.is_empty() {
        return Err("skill name required".to_string());
    }
    let skill_root = skill_dir.join(normalized);
    let metadata = fs::metadata(&skill_root)
        .await
        .map_err(|_| format!("skill not found: {normalized}"))?;
    if !metadata.is_dir() {
        return Err(format!("skill path is not a directory: {normalized}"));
    }
    Ok(read_installed_skill_item(&skill_root).await)
}

async fn remove_installed_skill(skill_dir: &Path, name: &str) -> Result<bool, String> {
    let normalized = name.trim();
    if normalized.is_empty() {
        return Err("skill name required".to_string());
    }
    let skill_root = skill_dir.join(normalized);
    match fs::metadata(&skill_root).await {
        Ok(metadata) => {
            if !metadata.is_dir() {
                return Err(format!("skill path is not a directory: {normalized}"));
            }
            fs::remove_dir_all(&skill_root)
                .await
                .map_err(|err| err.to_string())?;
            Ok(true)
        }
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(err) => Err(err.to_string()),
    }
}

async fn discover_sync_candidate(
    opencode_root: &Path,
    skill_dir: &Path,
    current: OpencodeSkillCatalogItem,
) -> Result<(SkillSyncCandidate, Option<PathBuf>), String> {
    let source = current
        .source
        .clone()
        .ok_or_else(|| format!("skill `{}` is missing source metadata", current.name))?;
    let source_request = source_info_to_skill_source(&source)?;
    let discovery =
        discover_skills_from_source(opencode_root, &source_request, skill_dir, true, 5000).await?;
    let candidate = discovery
        .items
        .iter()
        .find(|item| item.item.name == current.name)
        .cloned();
    let mut errors = discovery.errors;
    let action = if candidate.is_some() {
        "sync_ready".to_string()
    } else {
        errors.push(format!(
            "skill source no longer exposes `{}` under the recorded root",
            current.name
        ));
        "missing_from_source".to_string()
    };
    Ok((
        SkillSyncCandidate {
            current,
            candidate,
            errors,
            action,
        },
        discovery.cleanup_dir,
    ))
}

async fn discover_skills_from_source(
    opencode_root: &Path,
    source: &OpencodeSkillSource,
    installed_skill_dir: &Path,
    overwrite: bool,
    limit: usize,
) -> Result<SkillDiscoveryResult, String> {
    match source {
        OpencodeSkillSource::Local { path, root } => {
            let base = PathBuf::from(path.trim());
            let base = if base.is_absolute() {
                base
            } else {
                std::env::current_dir()
                    .unwrap_or_else(|_| PathBuf::from("."))
                    .join(base)
            };
            let scan_root = root
                .as_deref()
                .map(|value| base.join(value.trim()))
                .unwrap_or_else(|| base.clone());
            if !scan_root.is_dir() {
                return Err(format!(
                    "local path not found: {}",
                    scan_root.to_string_lossy()
                ));
            }

            let scan_root_for_worker = scan_root.clone();
            let dirs = tokio::task::spawn_blocking(move || {
                collect_skill_dirs(&scan_root_for_worker, limit)
            })
            .await
            .map_err(|err| err.to_string())?
            .map_err(|err| err.to_string())?;
            let source_info = build_local_source_info(&base, root.as_deref());
            let base_for_worker = base.clone();
            let installed_skill_dir_for_worker = installed_skill_dir.to_path_buf();
            let source_for_worker = source_info.clone();
            let dirs_for_worker = dirs.clone();
            let items = tokio::task::spawn_blocking(move || {
                collect_discovered_skills(
                    &base_for_worker,
                    dirs_for_worker,
                    &source_for_worker,
                    &installed_skill_dir_for_worker,
                    overwrite,
                )
            })
            .await
            .map_err(|err| err.to_string())?
            .map_err(|err| err.to_string())?;
            let mut result = SkillDiscoveryResult {
                items,
                errors: Vec::new(),
                cleanup_dir: None,
            };
            if result.items.is_empty() {
                result.errors.push(format!(
                    "no SKILL.md/skill.md found under local path: {}",
                    scan_root.to_string_lossy()
                ));
            }
            Ok(result)
        }
        OpencodeSkillSource::Git { url, r#ref, root } => {
            let url = url.trim().to_string();
            if url.is_empty() {
                return Err("git url required".to_string());
            }
            let git_ref = r#ref
                .as_deref()
                .map(|value| value.trim())
                .filter(|value| !value.is_empty());
            let scan_root_rel = root
                .as_deref()
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| "skills".to_string());

            let tmp_root = opencode_root.join("tmp");
            let clone_dir = tmp_root.join(format!("skillrepo_{}", Uuid::new_v4()));
            fs::create_dir_all(&clone_dir)
                .await
                .map_err(|err| err.to_string())?;

            let mut cmd = Command::new("git");
            cmd.env("GIT_TERMINAL_PROMPT", "0");
            cmd.arg("clone")
                .arg("--depth")
                .arg("1")
                .arg("--no-tags")
                .arg("--single-branch");
            if let Some(value) = git_ref {
                cmd.arg("--branch").arg(value);
            }
            cmd.arg(&url).arg(&clone_dir);
            cmd.stdout(std::process::Stdio::piped());
            cmd.stderr(std::process::Stdio::piped());

            let clone_timeout_ms = std::env::var("CMYKE_SKILL_INSTALL_GIT_TIMEOUT_MS")
                .ok()
                .and_then(|raw| raw.parse::<u64>().ok())
                .unwrap_or(600_000);
            let started = Instant::now();
            let output = timeout(Duration::from_millis(clone_timeout_ms), cmd.output())
                .await
                .map_err(|_| "git clone timeout".to_string())?
                .map_err(|err| err.to_string())?;
            if !output.status.success() {
                let _ = fs::remove_dir_all(&clone_dir).await;
                return Err(format!(
                    "git clone failed: {}",
                    String::from_utf8_lossy(&output.stderr)
                ));
            }
            tracing::info!(
                url = %url,
                ref_name = %git_ref.unwrap_or(""),
                duration_ms = started.elapsed().as_millis(),
                "skill repo cloned"
            );

            let scan_root = clone_dir.join(&scan_root_rel);
            if !scan_root.is_dir() {
                let _ = fs::remove_dir_all(&clone_dir).await;
                return Err(format!("scan root not found in repo: {}", scan_root_rel));
            }

            let scan_root_for_worker = scan_root.clone();
            let dirs = tokio::task::spawn_blocking(move || {
                collect_skill_dirs(&scan_root_for_worker, limit)
            })
            .await
            .map_err(|err| err.to_string())?
            .map_err(|err| err.to_string())?;
            let source_info = build_git_source_info(&url, git_ref, &scan_root_rel);
            let repo_root_for_worker = clone_dir.clone();
            let installed_skill_dir_for_worker = installed_skill_dir.to_path_buf();
            let source_for_worker = source_info.clone();
            let dirs_for_worker = dirs.clone();
            let items_result = tokio::task::spawn_blocking(move || {
                collect_discovered_skills(
                    &repo_root_for_worker,
                    dirs_for_worker,
                    &source_for_worker,
                    &installed_skill_dir_for_worker,
                    overwrite,
                )
            })
            .await
            .map_err(|err| err.to_string())?;
            let items = match items_result {
                Ok(items) => items,
                Err(err) => {
                    let _ = fs::remove_dir_all(&clone_dir).await;
                    return Err(err);
                }
            };
            let mut result = SkillDiscoveryResult {
                items,
                errors: Vec::new(),
                cleanup_dir: Some(clone_dir),
            };
            if result.items.is_empty() {
                result.errors.push(format!(
                    "no SKILL.md/skill.md found under repo scan root: {}",
                    scan_root_rel
                ));
            }
            Ok(result)
        }
    }
}

async fn opencode_skills_installed(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(payload): Json<OpencodeSkillsInstalledRequest>,
) -> Result<Json<OpencodeSkillsInstalledResponse>, (StatusCode, Json<ErrorResponse>)> {
    require_valid_pairing(&state, &headers, payload.pairing_token.as_deref()).await?;

    let container =
        resolve_workspace_container_root(payload.workspace.as_deref()).map_err(|err| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let opencode_root = container.join("_shared").join("opencode");

    let (config_path, config_dir) = ensure_opencode_project_config(&opencode_root)
        .await
        .map_err(|err| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let skill_dir = config_dir.join("skill");

    let mut items = Vec::new();
    if let Ok(mut rd) = fs::read_dir(&skill_dir).await {
        while let Ok(Some(entry)) = rd.next_entry().await {
            if let Ok(ft) = entry.file_type().await {
                if ft.is_dir() {
                    items.push(read_installed_skill_item(&entry.path()).await);
                }
            }
        }
    }
    items.sort_by(|left, right| {
        let left_key = format!(
            "{}:{}",
            left.display_name.to_ascii_lowercase(),
            left.name.to_ascii_lowercase()
        );
        let right_key = format!(
            "{}:{}",
            right.display_name.to_ascii_lowercase(),
            right.name.to_ascii_lowercase()
        );
        left_key.cmp(&right_key)
    });
    let mut skills = items
        .iter()
        .map(|item| item.name.clone())
        .collect::<Vec<_>>();
    skills.sort();

    Ok(Json(OpencodeSkillsInstalledResponse {
        ok: true,
        skills,
        items,
        opencode_root: opencode_root.to_string_lossy().to_string(),
        config_path: config_path.to_string_lossy().to_string(),
        config_dir: config_dir.to_string_lossy().to_string(),
        skill_dir: skill_dir.to_string_lossy().to_string(),
    }))
}

async fn opencode_skills_preview(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(payload): Json<OpencodeSkillsPreviewRequest>,
) -> Result<Json<OpencodeSkillsPreviewResponse>, (StatusCode, Json<ErrorResponse>)> {
    require_valid_pairing(&state, &headers, payload.pairing_token.as_deref()).await?;

    let container =
        resolve_workspace_container_root(payload.workspace.as_deref()).map_err(|err| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let opencode_root = container.join("_shared").join("opencode");
    let (_config_path, config_dir) = ensure_opencode_project_config(&opencode_root)
        .await
        .map_err(|err| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let skill_dir = config_dir.join("skill");
    let overwrite = payload.overwrite.unwrap_or(false);
    let limit = payload.limit.unwrap_or(500).clamp(1, 5000);
    let discovery = discover_skills_from_source(
        &opencode_root,
        &payload.source,
        &skill_dir,
        overwrite,
        limit,
    )
    .await
    .map_err(|err| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                ok: false,
                error: err,
            }),
        )
    })?;

    let mut items = discovery
        .items
        .into_iter()
        .map(|entry| entry.item)
        .collect::<Vec<_>>();
    items.sort_by(|left, right| {
        let left_key = format!(
            "{}:{}",
            left.display_name.to_ascii_lowercase(),
            left.name.to_ascii_lowercase()
        );
        let right_key = format!(
            "{}:{}",
            right.display_name.to_ascii_lowercase(),
            right.name.to_ascii_lowercase()
        );
        left_key.cmp(&right_key)
    });
    let response = OpencodeSkillsPreviewResponse {
        ok: discovery.errors.is_empty(),
        total: items.len(),
        ready: count_skill_items_with_status(&items, "ready"),
        conflicts: count_skill_items_with_status(&items, "conflict"),
        overwrites: count_skill_items_with_status(&items, "will_overwrite"),
        errors: discovery.errors,
        items,
        skill_dir: skill_dir.to_string_lossy().to_string(),
    };
    if let Some(cleanup_dir) = discovery.cleanup_dir {
        let _ = fs::remove_dir_all(cleanup_dir).await;
    }
    Ok(Json(response))
}

async fn opencode_skills_install(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(payload): Json<OpencodeSkillsInstallRequest>,
) -> Result<Json<OpencodeSkillsInstallResponse>, (StatusCode, Json<ErrorResponse>)> {
    require_valid_pairing(&state, &headers, payload.pairing_token.as_deref()).await?;

    let container =
        resolve_workspace_container_root(payload.workspace.as_deref()).map_err(|err| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let opencode_root = container.join("_shared").join("opencode");
    let (_config_path, config_dir) = ensure_opencode_project_config(&opencode_root)
        .await
        .map_err(|err| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let skill_dir = config_dir.join("skill");

    let trace_id = Uuid::new_v4().to_string();
    let skills_log_path = opencode_root.join("logs").join("opencode_skills.jsonl");
    let _ = fs::create_dir_all(opencode_root.join("logs")).await;
    let _ = append_jsonl_log(
        &skills_log_path,
        serde_json::json!({
            "event": "opencode_skills_install_start",
            "at": now_ts(),
            "trace_id": trace_id.as_str(),
            "skill_dir": skill_dir.to_string_lossy(),
            "overwrite": payload.overwrite.unwrap_or(false),
            "limit": payload.limit.unwrap_or(500),
        }),
    )
    .await;

    let overwrite = payload.overwrite.unwrap_or(false);
    let limit = payload.limit.unwrap_or(500).clamp(1, 5000);

    let mut installed = Vec::new();
    let mut skipped = Vec::new();
    let mut errors = Vec::new();

    let discovery = discover_skills_from_source(
        &opencode_root,
        &payload.source,
        &skill_dir,
        overwrite,
        limit,
    )
    .await
    .map_err(|err| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                ok: false,
                error: err,
            }),
        )
    })?;
    errors.extend(discovery.errors);

    for discovered in &discovery.items {
        let name = discovered.item.name.clone();
        let dest = skill_dir.join(&name);
        if dest.exists() && !overwrite {
            skipped.push(name);
            continue;
        }
        if dest.exists() && overwrite {
            let _ = fs::remove_dir_all(&dest).await;
        }
        let src = discovered.source_dir.clone();
        let dst = dest.clone();
        let res = tokio::task::spawn_blocking(move || copy_dir_recursive(&src, &dst)).await;
        match res {
            Ok(Ok(())) => {
                if let Err(err) = write_skill_manifest(&dest, &discovered.item).await {
                    let _ = fs::remove_dir_all(&dest).await;
                    errors.push(format!("{}: {}", name, err));
                    continue;
                }
                installed.push(name);
            }
            Ok(Err(err)) => errors.push(format!("{}: {}", name, err)),
            Err(err) => errors.push(format!("{}: {}", name, err)),
        }
    }
    if let Some(cleanup_dir) = discovery.cleanup_dir {
        let _ = fs::remove_dir_all(cleanup_dir).await;
    }

    installed.sort();
    skipped.sort();
    errors.sort();

    let _ = append_jsonl_log(
        &skills_log_path,
        serde_json::json!({
            "event": "opencode_skills_install_finish",
            "at": now_ts(),
            "trace_id": trace_id.as_str(),
            "installed": installed.len(),
            "skipped": skipped.len(),
            "errors": errors.len(),
        }),
    )
    .await;

    Ok(Json(OpencodeSkillsInstallResponse {
        ok: errors.is_empty(),
        installed,
        skipped,
        errors,
        skill_dir: skill_dir.to_string_lossy().to_string(),
    }))
}

async fn opencode_skills_remove(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(payload): Json<OpencodeSkillNamedRequest>,
) -> Result<Json<OpencodeSkillRemoveResponse>, (StatusCode, Json<ErrorResponse>)> {
    require_valid_pairing(&state, &headers, payload.pairing_token.as_deref()).await?;

    let container =
        resolve_workspace_container_root(payload.workspace.as_deref()).map_err(|err| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let opencode_root = container.join("_shared").join("opencode");
    let (_config_path, config_dir) = ensure_opencode_project_config(&opencode_root)
        .await
        .map_err(|err| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let skill_dir = config_dir.join("skill");
    let removed = remove_installed_skill(&skill_dir, &payload.name)
        .await
        .map_err(|err| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    Ok(Json(OpencodeSkillRemoveResponse {
        ok: removed,
        removed,
        name: payload.name.trim().to_string(),
        errors: Vec::new(),
        skill_dir: skill_dir.to_string_lossy().to_string(),
    }))
}

async fn opencode_skills_sync_preview(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(payload): Json<OpencodeSkillNamedRequest>,
) -> Result<Json<OpencodeSkillSyncPreviewResponse>, (StatusCode, Json<ErrorResponse>)> {
    require_valid_pairing(&state, &headers, payload.pairing_token.as_deref()).await?;

    let container =
        resolve_workspace_container_root(payload.workspace.as_deref()).map_err(|err| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let opencode_root = container.join("_shared").join("opencode");
    let (_config_path, config_dir) = ensure_opencode_project_config(&opencode_root)
        .await
        .map_err(|err| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let skill_dir = config_dir.join("skill");
    let current = resolve_installed_skill_item(&skill_dir, &payload.name)
        .await
        .map_err(|err| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let (sync_candidate, cleanup_dir) =
        discover_sync_candidate(&opencode_root, &skill_dir, current)
            .await
            .map_err(|err| {
                (
                    StatusCode::BAD_REQUEST,
                    Json(ErrorResponse {
                        ok: false,
                        error: err,
                    }),
                )
            })?;
    if let Some(cleanup_dir) = cleanup_dir {
        let _ = fs::remove_dir_all(cleanup_dir).await;
    }
    let candidate_item = sync_candidate.candidate.map(|mut candidate| {
        candidate.item.status = "sync_ready".to_string();
        candidate.item
    });
    Ok(Json(OpencodeSkillSyncPreviewResponse {
        ok: candidate_item.is_some() && sync_candidate.errors.is_empty(),
        name: sync_candidate.current.name.clone(),
        action: sync_candidate.action,
        current: sync_candidate.current,
        candidate: candidate_item,
        errors: sync_candidate.errors,
        skill_dir: skill_dir.to_string_lossy().to_string(),
    }))
}

async fn opencode_skills_sync(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(payload): Json<OpencodeSkillNamedRequest>,
) -> Result<Json<OpencodeSkillSyncResponse>, (StatusCode, Json<ErrorResponse>)> {
    require_valid_pairing(&state, &headers, payload.pairing_token.as_deref()).await?;

    let container =
        resolve_workspace_container_root(payload.workspace.as_deref()).map_err(|err| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let opencode_root = container.join("_shared").join("opencode");
    let (_config_path, config_dir) = ensure_opencode_project_config(&opencode_root)
        .await
        .map_err(|err| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let skill_dir = config_dir.join("skill");
    let current = resolve_installed_skill_item(&skill_dir, &payload.name)
        .await
        .map_err(|err| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
    let name = current.name.clone();
    let (sync_candidate, cleanup_dir) =
        discover_sync_candidate(&opencode_root, &skill_dir, current)
            .await
            .map_err(|err| {
                (
                    StatusCode::BAD_REQUEST,
                    Json(ErrorResponse {
                        ok: false,
                        error: err,
                    }),
                )
            })?;
    let mut errors = sync_candidate.errors.clone();
    let candidate = sync_candidate.candidate.ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                ok: false,
                error: if errors.is_empty() {
                    format!("skill source no longer exposes `{name}`")
                } else {
                    errors.join("; ")
                },
            }),
        )
    })?;
    let dest = skill_dir.join(&name);
    let _ = fs::remove_dir_all(&dest).await;
    let src = candidate.source_dir.clone();
    let dst = dest.clone();
    let copy_result = tokio::task::spawn_blocking(move || copy_dir_recursive(&src, &dst))
        .await
        .map_err(|err| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    ok: false,
                    error: err.to_string(),
                }),
            )
        })?;
    if let Err(err) = copy_result {
        if let Some(cleanup_dir) = cleanup_dir {
            let _ = fs::remove_dir_all(cleanup_dir).await;
        }
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                ok: false,
                error: err.to_string(),
            }),
        ));
    }
    if let Err(err) = write_skill_manifest(&dest, &candidate.item).await {
        let _ = fs::remove_dir_all(&dest).await;
        if let Some(cleanup_dir) = cleanup_dir {
            let _ = fs::remove_dir_all(cleanup_dir).await;
        }
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                ok: false,
                error: err,
            }),
        ));
    }
    let refreshed_item = read_installed_skill_item(&dest).await;
    if let Some(cleanup_dir) = cleanup_dir {
        let _ = fs::remove_dir_all(cleanup_dir).await;
    }
    Ok(Json(OpencodeSkillSyncResponse {
        ok: errors.is_empty(),
        name,
        action: "synced".to_string(),
        item: Some(refreshed_item),
        errors: std::mem::take(&mut errors),
        skill_dir: skill_dir.to_string_lossy().to_string(),
    }))
}

fn build_app(shared_state: SharedState) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/api/v1/health", get(health))
        .route("/api/v1/gateway/info", get(gateway_info))
        .route("/api/v1/gateway/capabilities", get(gateway_capabilities))
        .route("/api/v1/gateway/pairing/create", post(pairing_create))
        .route("/api/v1/gateway/pairing/verify", post(pairing_verify))
        .route("/api/v1/gateway/pairing/list", get(pairing_list))
        .route("/api/v1/gateway/inbound", post(inbound_message))
        .route("/api/v1/gateway/outbound", post(outbound_message))
        .route("/api/v1/opencode/run", post(opencode_run))
        .route("/api/v1/opencode/cancel", post(opencode_cancel))
        .route(
            "/api/v1/opencode/skills/installed",
            post(opencode_skills_installed),
        )
        .route(
            "/api/v1/opencode/skills/preview",
            post(opencode_skills_preview),
        )
        .route(
            "/api/v1/opencode/skills/install",
            post(opencode_skills_install),
        )
        .route(
            "/api/v1/opencode/skills/remove",
            post(opencode_skills_remove),
        )
        .route(
            "/api/v1/opencode/skills/sync/preview",
            post(opencode_skills_sync_preview),
        )
        .route("/api/v1/opencode/skills/sync", post(opencode_skills_sync))
        .with_state(shared_state)
}

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let shared_state: SharedState = Arc::new(Mutex::new(GatewayState::default()));
    let app = build_app(shared_state);

    let addr = resolve_listen_addr();
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    tracing::info!("CMYKE Rust backend listening on http://{}", addr);
    axum::serve(listener, app).await.unwrap();
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        body::{to_bytes, Body},
        http::{Request, StatusCode},
    };
    use tower::util::ServiceExt;

    fn test_shared_state() -> SharedState {
        Arc::new(Mutex::new(GatewayState::default()))
    }

    async fn insert_test_pairing(state: &SharedState, token: &str) {
        let now = now_ts();
        let pairing = Pairing {
            id: "pairing-1".to_string(),
            token: token.to_string(),
            mode: "desktop".to_string(),
            label: Some("test".to_string()),
            created_at: now,
            expires_at: now + 3600,
        };
        state
            .lock()
            .await
            .pairings
            .insert(pairing.id.clone(), pairing);
    }

    #[test]
    fn split_markdown_frontmatter_extracts_yaml_and_body() {
        let markdown = "---\nname: Git Summary\nauthor: zweack\n---\n# Title\n\nBody text.\n";

        let (frontmatter, body) = split_markdown_frontmatter(markdown);

        assert_eq!(
            frontmatter.as_deref(),
            Some("name: Git Summary\nauthor: zweack")
        );
        assert_eq!(body, "# Title\n\nBody text.");
    }

    #[test]
    fn parse_skill_doc_prefers_frontmatter_and_extracts_requirements() {
        let markdown = r#"---
name: Git Summary
description: Summarize repository changes.
author: zweack
version: 1.2.0
homepage: https://example.com/skills/git-summary
tags:
  - git
  - summary
user-invocable: true
metadata:
  openclaw:
    requires:
      bins: [git, python]
      env: GITHUB_TOKEN, OPENAI_API_KEY
      os: [windows, linux]
---
# Ignored title

Ignored body paragraph.
"#;

        let parsed = parse_skill_doc(markdown, "fallback", Some("skills/zweack/git-summary"));

        assert_eq!(parsed.display_name, "Git Summary");
        assert_eq!(
            parsed.description.as_deref(),
            Some("Summarize repository changes.")
        );
        assert_eq!(parsed.author.as_deref(), Some("zweack"));
        assert_eq!(parsed.version.as_deref(), Some("1.2.0"));
        assert_eq!(
            parsed.homepage.as_deref(),
            Some("https://example.com/skills/git-summary")
        );
        assert_eq!(parsed.tags, vec!["git", "summary"]);
        assert_eq!(parsed.user_invocable, Some(true));
        assert!(parsed.has_frontmatter);
        assert_eq!(parsed.requirements.bins, vec!["git", "python"]);
        assert_eq!(
            parsed.requirements.env,
            vec!["GITHUB_TOKEN", "OPENAI_API_KEY"]
        );
        assert_eq!(parsed.requirements.os, vec!["windows", "linux"]);
    }

    #[test]
    fn parse_skill_doc_falls_back_to_markdown_and_relative_path_author() {
        let markdown =
            "# Memory Qdrant\n\nStore memory in qdrant with local-first settings.\n\n- setup\n";

        let parsed = parse_skill_doc(markdown, "fallback", Some("skills/zuiho-kai/memory-qdrant"));

        assert_eq!(parsed.display_name, "Memory Qdrant");
        assert_eq!(
            parsed.description.as_deref(),
            Some("Store memory in qdrant with local-first settings.")
        );
        assert_eq!(parsed.author.as_deref(), Some("zuiho-kai"));
        assert!(!parsed.has_frontmatter);
        assert!(parsed.requirements.bins.is_empty());
    }

    #[test]
    fn derive_skill_name_preserves_nested_variant_segments() {
        let repo_root = Path::new("repo");
        let skill_dir = repo_root
            .join("skills")
            .join("author")
            .join("skill")
            .join("variant v2");

        let name = derive_skill_name(repo_root, &skill_dir);

        assert_eq!(name, "author__skill__variant_v2");
    }

    #[test]
    fn source_info_to_skill_source_rebuilds_git_source() {
        let source = OpencodeSkillSourceInfo {
            kind: "git".to_string(),
            label: "acme/skills".to_string(),
            location: "https://github.com/acme/skills.git".to_string(),
            root: Some("skills".to_string()),
            r#ref: Some("main".to_string()),
        };

        let rebuilt = source_info_to_skill_source(&source).unwrap();

        match rebuilt {
            OpencodeSkillSource::Git { url, r#ref, root } => {
                assert_eq!(url, "https://github.com/acme/skills.git");
                assert_eq!(r#ref.as_deref(), Some("main"));
                assert_eq!(root.as_deref(), Some("skills"));
            }
            _ => panic!("expected git source"),
        }
    }

    #[test]
    fn source_info_to_skill_source_rejects_unknown_type() {
        let source = OpencodeSkillSourceInfo {
            kind: "zip".to_string(),
            label: "archive".to_string(),
            location: "skills.zip".to_string(),
            root: None,
            r#ref: None,
        };

        let err = source_info_to_skill_source(&source).unwrap_err();

        assert!(err.contains("unsupported skill source type"));
    }

    #[test]
    fn normalize_cancel_group_trims_and_drops_empty_values() {
        assert_eq!(
            normalize_cancel_group(Some("  active-group  ")),
            Some("active-group".to_string())
        );
        assert_eq!(normalize_cancel_group(Some("   ")), None);
        assert_eq!(normalize_cancel_group(None), None);
    }

    #[test]
    fn cleanup_cancellations_removes_expired_entries() {
        let now = now_ts();
        let mut state = GatewayState::default();
        state
            .canceled_sessions
            .insert("expired-session".to_string(), now - 1);
        state
            .canceled_sessions
            .insert("active-session".to_string(), now + 60);
        state
            .canceled_groups
            .insert("expired-group".to_string(), now - 1);
        state
            .canceled_groups
            .insert("active-group".to_string(), now + 60);

        cleanup_cancellations(&mut state);

        assert!(!state.canceled_sessions.contains_key("expired-session"));
        assert!(state.canceled_sessions.contains_key("active-session"));
        assert!(!state.canceled_groups.contains_key("expired-group"));
        assert!(state.canceled_groups.contains_key("active-group"));
    }

    #[tokio::test]
    async fn is_run_canceled_checks_session_and_group_flags() {
        let now = now_ts();
        let state = Arc::new(Mutex::new(GatewayState::default()));
        {
            let mut guard = state.lock().await;
            guard
                .canceled_sessions
                .insert("session-a".to_string(), now + 60);
            guard
                .canceled_groups
                .insert("group-a".to_string(), now + 60);
        }

        assert!(is_run_canceled(&state, "session-a", None).await);
        assert!(is_run_canceled(&state, "session-b", Some("group-a")).await);
        assert!(!is_run_canceled(&state, "session-b", Some("group-b")).await);
    }

    #[tokio::test]
    async fn gateway_capabilities_reports_runtime_snapshot_and_routes() {
        let state = test_shared_state();
        insert_test_pairing(&state, "pairing-token").await;

        let response = build_app(state)
            .oneshot(
                Request::builder()
                    .uri("/api/v1/gateway/capabilities")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let payload: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(payload["ok"], true);
        assert!(payload["routes"]
            .as_array()
            .unwrap()
            .iter()
            .any(|route| route == "/api/v1/opencode/cancel"));
        assert!(payload["features"]
            .as_array()
            .unwrap()
            .iter()
            .any(|feature| feature == "interruptible_run"));
        assert_eq!(payload["runtime"]["pairings_active"], 1);
    }

    #[tokio::test]
    async fn opencode_cancel_rejects_requests_without_pairing_token() {
        let response = build_app(test_shared_state())
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/v1/opencode/cancel")
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"session_id":"session-a"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);

        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let payload: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(payload["error"], "pairing token required");
    }

    #[tokio::test]
    async fn opencode_cancel_accepts_header_token_and_normalizes_group() {
        let state = test_shared_state();
        insert_test_pairing(&state, "pairing-token").await;

        let response = build_app(state.clone())
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/v1/opencode/cancel")
                    .header("content-type", "application/json")
                    .header("x-pairing-token", "pairing-token")
                    .body(Body::from(
                        r#"{"cancel_group":"  active-group  ","ttl_sec":10,"reason":"stop"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let payload: OpencodeCancelResponse = serde_json::from_slice(&body).unwrap();
        assert!(payload.ok);
        assert!(payload.accepted);
        assert_eq!(payload.cancel_group.as_deref(), Some("active-group"));
        assert_eq!(payload.reason.as_deref(), Some("stop"));

        let guard = state.lock().await;
        let expires_at = guard.canceled_groups.get("active-group").copied().unwrap();
        assert_eq!(expires_at, payload.expires_at);
        assert!(payload.expires_at >= now_ts() + 30);
    }
}
