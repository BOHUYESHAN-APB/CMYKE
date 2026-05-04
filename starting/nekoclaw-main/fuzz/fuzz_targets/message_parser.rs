#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    // Fuzz message parsing喵
    if let Ok(message) = std::str::from_utf8(data) {
        // 检查消息边界和有效性喵
        if !message.is_empty() && message.len() < 10000 {
            // 检查特殊字符喵
            if !message.contains('\0') {
                // 检查重复模式（防止 DoS）喵
                let chars: Vec<char> = message.chars().collect();
                if chars.len() > 10 {
                    let mut repeated = 0;
                    for i in 5..chars.len() {
                        if chars[i] == chars[i-1] && chars[i-1] == chars[i-2] &&
                           chars[i-2] == chars[i-3] && chars[i-3] == chars[i-4] {
                            repeated += 1;
                        }
                    }
                    // 如果重复太多次，就拒绝喵
                    if repeated * 5 < chars.len() {
                        // 这是一个可能的消息喵
                        let _ = message.to_lowercase();
                        let _ = message.to_uppercase();
                        let _ = message.trim();
                    }
                }
            }
        }
    }
});
