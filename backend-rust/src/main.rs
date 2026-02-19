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
    let workspace_root =
        resolve_workspace_root(payload.workspace.as_deref(), session_id).map_err(|err| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    ok: false,
                    error: err,
                }),
            )
        })?;
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
    let opencode_log_path = workspace_root.join("logs").join("opencode_runs.jsonl");
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

    let mut cmd = Command::new("opencode");
    cmd.arg("run");
    cmd.arg(message);
    cmd.current_dir(&cwd);
    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());

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
            let response = OpencodeRunResponse {
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
                let response = OpencodeRunResponse {
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

    let response = OpencodeRunResponse {
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

fn resolve_workspace_root(workspace: Option<&str>, session_id: &str) -> Result<PathBuf, String> {
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
    Ok(root.join(session_id))
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
        .with_state(shared_state);

    let addr = resolve_listen_addr();
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    tracing::info!("CMYKE Rust backend listening on http://{}", addr);
    axum::serve(listener, app).await.unwrap();
}
