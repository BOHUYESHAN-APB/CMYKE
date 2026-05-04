#![no_main]

use libfuzzer_sys::fuzz_target;
use nekoclaw::core::traits::Config;

fuzz_target!(|data: &[u8]| {
    // Fuzz config parsing喵
    if let Ok(config_string) = std::str::from_utf8(data) {
        // 尝试解析各种格式的配置喵
        if data.len() < 10000 {
            // JSON 格式
            if let Ok(json_value) = serde_json::from_str::<serde_json::Value>(config_string) {
                // 验证 JSON 结构喵
                let _ = json_value.get("api_key");
                let _ = json_value.get("default_provider");
            }
        }
    }
});
