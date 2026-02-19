use axum::{http::StatusCode, routing::{get, post}, Router};

pub fn router() -> Router {
    Router::new()
        .route("/api/v1/gateway/info", get(not_implemented))
        .route("/api/v1/gateway/capabilities", get(not_implemented))
        .route("/api/v1/events", get(not_implemented))
        .route("/api/v1/messages/inbound", post(not_implemented))
        .route("/api/v1/messages/outbound", post(not_implemented))
        .route("/api/v1/session-map/resolve", post(not_implemented))
        .route("/api/v1/session-map/:map_id", get(not_implemented))
        .route("/api/v1/session-map/:map_id", axum::routing::put(not_implemented))
        .route("/api/v1/session-map/:map_id", axum::routing::delete(not_implemented))
        .route("/api/v1/pairing/lan/offer", post(not_implemented))
        .route("/api/v1/pairing/lan/accept", post(not_implemented))
        .route("/api/v1/pairing/wan/create", post(not_implemented))
        .route("/api/v1/pairing/wan/rotate", post(not_implemented))
        .route("/api/v1/pairing/:pairing_id", get(not_implemented))
}

async fn not_implemented() -> StatusCode {
    StatusCode::NOT_IMPLEMENTED
}
