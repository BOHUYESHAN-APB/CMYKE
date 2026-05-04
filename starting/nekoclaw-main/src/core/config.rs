/*!
 * 配置加载模块
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15 17:40 JST
 */

use crate::core::traits::{Config, Result};
use std::path::Path;

impl Default for Config {
    fn default() -> Self {
        Config {
            version: "0.1.0".to_string(),
            api_key: None,
            default_provider: "openai".to_string(),
            default_model: "gpt-4".to_string(),
            default_temperature: 0.7,
            workspace: dirs::home_dir()
                .unwrap_or_else(|| std::path::PathBuf::from("/home/gengetsu"))
                .join(".nekoclaw/workspace"),
            providers: None,
            discord_config: None,
            gateway_port: Some(8080),
            gateway_bind: Some("127.0.0.1".to_string()),
        }
    }
}

pub fn load(config_dir: &Path) -> Result<Config> {
    // 优先尝试 config.json
    let json_path = config_dir.join("config.json");
    if json_path.exists() {
        let content = std::fs::read_to_string(&json_path)
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        let config: Config = serde_json::from_str(&content)
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        return Ok(config);
    }

    // 其次尝试 config.toml
    let toml_path = config_dir.join("config.toml");
    if toml_path.exists() {
        let content = std::fs::read_to_string(&toml_path)
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        let config: Config = toml::from_str(&content)
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        return Ok(config);
    }

    // 都不存在则返回默认配置
    Ok(Config::default())
}

pub fn save(config_dir: &Path, config: &Config) -> Result<()> {
    let config_path = config_dir.join("config.json");
    std::fs::create_dir_all(config_dir)
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;

    let content = serde_json::to_string_pretty(config)
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;

    std::fs::write(&config_path, content)
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;

    Ok(())
}
