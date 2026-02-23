use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, VecDeque},
    net::SocketAddr,
    path::{Component, Path, PathBuf},
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use std::io;
use tokio::{
    fs,
    io::{AsyncReadExt, AsyncWriteExt},
    time::timeout,
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
struct OpencodeSkillsInstalledRequest {
    pairing_token: Option<String>,
    workspace: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpencodeSkillsInstalledResponse {
    ok: bool,
    skills: Vec<String>,
    opencode_root: String,
    config_path: String,
    config_dir: String,
    skill_dir: String,
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
struct OpencodeSkillsInstallResponse {
    ok: bool,
    installed: Vec<String>,
    skipped: Vec<String>,
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
    let workspace_container =
        resolve_workspace_container_root(payload.workspace.as_deref()).map_err(|err| {
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
    let trace_id_fs = sanitize_trace_id(&trace_id);
    let run_started_at = SystemTime::now()
        .checked_sub(Duration::from_secs(2))
        .unwrap_or_else(|| SystemTime::now());
    let opencode_log_path = workspace_root.join("logs").join("opencode_runs.jsonl");
    let opencode_artifact_dir = workspace_root.join("logs").join("opencode_runs");
    let _ = fs::create_dir_all(&opencode_artifact_dir).await;
    let opencode_artifact_path = opencode_artifact_dir.join(format!("{trace_id_fs}.json"));
    if let Err(err) = append_jsonl_log(
        &opencode_log_path,
        serde_json::json!({
            "event": "opencode_run_start",
            "at": now_ts(),
            "trace_id": trace_id.as_str(),
            "session_id": session_id,
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

    let mut timed_out = false;
    let status = match timeout(Duration::from_millis(timeout_ms), child.wait()).await {
        Ok(result) => match result {
            Ok(status) => Some(status),
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
                    "opencode run wait failed"
                );
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
                    false,
                    &response,
                );
                if let Err(err) = write_pretty_json(&opencode_artifact_path, artifact).await {
                    tracing::warn!("failed to write opencode artifact: {}", err);
                }
                return Ok(Json(response));
            }
        },
        Err(_) => {
            timed_out = true;
            let _ = child.kill().await;
            let _ = child.wait().await;
            None
        }
    };

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
    } else {
        String::from_utf8_lossy(&stderr_bytes).to_string()
    };

    let exit_code = status.and_then(|status| status.code()).unwrap_or(-1);
    let ok = !timed_out && exit_code == 0;
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
    let mut files_written = collect_files_written_since(&workspace_root, &cwd, run_started_at, 2000).await;
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
        duration_ms = response.duration_ms,
        log_path = %response.log_path,
        "opencode run finished"
    );

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
            return sanitize_skill_name(&format!("{}__{}", parts[1], parts[2]));
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

    let mut skills = Vec::new();
    if let Ok(mut rd) = fs::read_dir(&skill_dir).await {
        while let Ok(Some(entry)) = rd.next_entry().await {
            if let Ok(ft) = entry.file_type().await {
                if ft.is_dir() {
                    if let Some(name) = entry.file_name().to_str() {
                        skills.push(name.to_string());
                    }
                }
            }
        }
    }
    skills.sort();

    Ok(Json(OpencodeSkillsInstalledResponse {
        ok: true,
        skills,
        opencode_root: opencode_root.to_string_lossy().to_string(),
        config_path: config_path.to_string_lossy().to_string(),
        config_dir: config_dir.to_string_lossy().to_string(),
        skill_dir: skill_dir.to_string_lossy().to_string(),
    }))
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

    match payload.source {
        OpencodeSkillSource::Local { path, root } => {
            let base = PathBuf::from(path.trim());
            let base = if base.is_absolute() {
                base
            } else {
                std::env::current_dir()
                    .unwrap_or_else(|_| PathBuf::from("."))
                    .join(base)
            };
            let scan_root = if let Some(r) = root.as_deref() {
                base.join(r.trim())
            } else {
                base.clone()
            };
            if !scan_root.is_dir() {
                return Err((
                    StatusCode::BAD_REQUEST,
                    Json(ErrorResponse {
                        ok: false,
                        error: format!("local path not found: {}", scan_root.to_string_lossy()),
                    }),
                ));
            }

            let scan_root_for_worker = scan_root.clone();
            let dirs = tokio::task::spawn_blocking(move || {
                collect_skill_dirs(&scan_root_for_worker, limit)
            })
            .await
            .map_err(|err| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        ok: false,
                        error: err.to_string(),
                    }),
                )
            })?
            .map_err(|err| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        ok: false,
                        error: err,
                    }),
                )
            })?;

            if dirs.is_empty() {
                errors.push(format!(
                    "no SKILL.md/skill.md found under local path: {}",
                    scan_root.to_string_lossy()
                ));
            }

            for dir in dirs {
                let name = derive_skill_name(&base, &dir);
                let dest = skill_dir.join(&name);
                if dest.exists() && !overwrite {
                    skipped.push(name);
                    continue;
                }
                if dest.exists() && overwrite {
                    let _ = fs::remove_dir_all(&dest).await;
                }
                let src = dir.clone();
                let dst = dest.clone();
                let res = tokio::task::spawn_blocking(move || copy_dir_recursive(&src, &dst)).await;
                match res {
                    Ok(Ok(())) => installed.push(name),
                    Ok(Err(e)) => errors.push(format!("{}: {}", name, e)),
                    Err(e) => errors.push(format!("{}: {}", name, e)),
                }
            }
        }
        OpencodeSkillSource::Git { url, r#ref, root } => {
            let url = url.trim().to_string();
            if url.is_empty() {
                return Err((
                    StatusCode::BAD_REQUEST,
                    Json(ErrorResponse {
                        ok: false,
                        error: "git url required".to_string(),
                    }),
                ));
            }
            let git_ref = r#ref.as_deref().map(|s| s.trim()).filter(|s| !s.is_empty());
            let scan_root_rel = root
                .as_deref()
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| "skills".to_string());

            let tmp_root = opencode_root.join("tmp");
            let clone_dir = tmp_root.join(format!("skillrepo_{}", Uuid::new_v4()));
            if let Err(err) = fs::create_dir_all(&clone_dir).await {
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        ok: false,
                        error: err.to_string(),
                    }),
                ));
            }

            let mut cmd = Command::new("git");
            cmd.env("GIT_TERMINAL_PROMPT", "0");
            cmd.arg("clone")
                .arg("--depth")
                .arg("1")
                .arg("--no-tags")
                .arg("--single-branch");
            if let Some(r) = git_ref {
                cmd.arg("--branch").arg(r);
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
                .map_err(|_| {
                    (
                        StatusCode::REQUEST_TIMEOUT,
                        Json(ErrorResponse {
                            ok: false,
                            error: "git clone timeout".to_string(),
                        }),
                    )
                })?
                .map_err(|err| {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        Json(ErrorResponse {
                            ok: false,
                            error: err.to_string(),
                        }),
                    )
                })?;
            if !output.status.success() {
                let _ = fs::remove_dir_all(&clone_dir).await;
                return Err((
                    StatusCode::BAD_REQUEST,
                    Json(ErrorResponse {
                        ok: false,
                        error: format!(
                            "git clone failed: {}",
                            String::from_utf8_lossy(&output.stderr)
                        ),
                    }),
                ));
            }
            tracing::info!(
                url = %url,
                ref_name = %git_ref.unwrap_or(""),
                duration_ms = started.elapsed().as_millis(),
                "skill repo cloned"
            );

            let repo_root = clone_dir.clone();
            let scan_root = clone_dir.join(&scan_root_rel);
            if !scan_root.is_dir() {
                let _ = fs::remove_dir_all(&clone_dir).await;
                return Err((
                    StatusCode::BAD_REQUEST,
                    Json(ErrorResponse {
                        ok: false,
                        error: format!("scan root not found in repo: {}", scan_root_rel),
                    }),
                ));
            }

            let repo_hint_name = parse_github_owner_repo(&url).map(|(owner, repo)| {
                sanitize_skill_name(&format!("{owner}__{repo}"))
            });

            let scan_root_for_worker = scan_root.clone();
            let dirs = tokio::task::spawn_blocking(move || {
                collect_skill_dirs(&scan_root_for_worker, limit)
            })
            .await
            .map_err(|err| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        ok: false,
                        error: err.to_string(),
                    }),
                )
            })?
            .map_err(|err| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        ok: false,
                        error: err,
                    }),
                )
            })?;

            if dirs.is_empty() {
                errors.push(format!(
                    "no SKILL.md/skill.md found under repo scan root: {}",
                    scan_root_rel
                ));
            }

            for dir in dirs {
                let mut name = derive_skill_name(&repo_root, &dir);
                // If the SKILL.md is at the repo root (or scan root), prefer a stable name
                // derived from the repo URL (owner__repo) instead of the temp folder name.
                if (dir == repo_root || dir == scan_root) && repo_hint_name.is_some() {
                    name = repo_hint_name.clone().unwrap();
                }
                let dest = skill_dir.join(&name);
                if dest.exists() && !overwrite {
                    skipped.push(name);
                    continue;
                }
                if dest.exists() && overwrite {
                    let _ = fs::remove_dir_all(&dest).await;
                }
                let src = dir.clone();
                let dst = dest.clone();
                let res = tokio::task::spawn_blocking(move || copy_dir_recursive(&src, &dst)).await;
                match res {
                    Ok(Ok(())) => installed.push(name),
                    Ok(Err(e)) => errors.push(format!("{}: {}", name, e)),
                    Err(e) => errors.push(format!("{}: {}", name, e)),
                }
            }

            let _ = fs::remove_dir_all(&clone_dir).await;
        }
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

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let shared_state: SharedState = Arc::new(Mutex::new(GatewayState::default()));
    let app = Router::new()
        .route("/health", get(health))
        .route("/api/v1/health", get(health))
        .route("/api/v1/gateway/pairing/create", post(pairing_create))
        .route("/api/v1/gateway/pairing/verify", post(pairing_verify))
        .route("/api/v1/gateway/pairing/list", get(pairing_list))
        .route("/api/v1/gateway/inbound", post(inbound_message))
        .route("/api/v1/gateway/outbound", post(outbound_message))
        .route("/api/v1/opencode/run", post(opencode_run))
        .route(
            "/api/v1/opencode/skills/installed",
            post(opencode_skills_installed),
        )
        .route("/api/v1/opencode/skills/install", post(opencode_skills_install))
        .with_state(shared_state);

    let addr = resolve_listen_addr();
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    tracing::info!("CMYKE Rust backend listening on http://{}", addr);
    axum::serve(listener, app).await.unwrap();
}
