//! # FileSystem Tool
//!
//! 📁 安全的文件系统操作工具
//!
//! @诺诺 的文件系统工具实现喵
//!
//! ## 功能
//! - 读取文件内容
//! - 写入文件（需要授权）
//! - 列出目录
//! - 获取文件信息
//!
//! 🔒 SAFETY: 受路径遍历保护，操作限制在 workspace
//!
//! Author: 诺诺 (Nono) ⚡

use super::mcp::{Tool, ToolDescription, ToolError, ToolResult};
use serde_json::json;
use std::path::{Path, PathBuf};

/// 🔒 SAFETY: FileSystem 工具喵
pub struct FileSystemTool {
    /// 工作目录（限制访问范围）
    workspace: PathBuf,
}

impl FileSystemTool {
    /// 🔒 SAFETY: 创建新的 FileSystem 工具喵
    pub fn new(workspace: &Path) -> Self {
        Self {
            workspace: workspace.to_path_buf(),
        }
    }

    /// 🔒 SAFETY: 解析路径（防止路径遍历）喵
    fn resolve_path(&self, path: &str) -> Result<PathBuf, ToolError> {
        let input_path = Path::new(path);

        // 检测路径遍历攻击
        if path.contains("..") {
            return Err(ToolError::Other("Path traversal detected".to_string()));
        }

        // 构建完整路径
        let full_path = self.workspace.join(input_path);

        // 确保在工作目录内 - 检查完整路径而不是输入路径
        let canonical_full = full_path.canonicalize().unwrap_or_else(|_| full_path.clone());
        let canonical_workspace = self.workspace.canonicalize().unwrap_or_else(|_| self.workspace.clone());

        if !canonical_full.starts_with(&canonical_workspace) {
            return Err(ToolError::PermissionDenied(
                "Access outside workspace not allowed".to_string(),
            ));
        }

        Ok(full_path)
    }
}

#[async_trait::async_trait]
impl Tool for FileSystemTool {
    fn describe(&self) -> ToolDescription {
        ToolDescription {
            name: "fs_read".to_string(),
            description: "Read file content from workspace. Prevents path traversal attacks.".to_string(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "File path relative to workspace"
                    }
                },
                "required": ["path"]
            }),
            category: Some("filesystem".to_string()),
            dangerous: false,
            required_permissions: None,
        }
    }

    fn validate_input(&self, input: &serde_json::Value) -> Result<(), ToolError> {
        if !input.is_object() {
            return Err(ToolError::ValidationError(
                "Input must be a JSON object".to_string(),
            ));
        }

        if input.get("path").is_none() {
            return Err(ToolError::ValidationError(
                "Missing required field: 'path'".to_string(),
            ));
        }

        Ok(())
    }

    async fn execute(&self, input: serde_json::Value) -> Result<ToolResult, ToolError> {
        let start = std::time::Instant::now();

        let path = input
            .get("path")
            .and_then(|p| p.as_str())
            .ok_or_else(|| ToolError::ValidationError("Invalid 'path' field".to_string()))?;

        // 解析并验证路径
        let full_path = self.resolve_path(path)?;

        // 读取文件
        let content = tokio::fs::read_to_string(&full_path)
            .await
            .map_err(|e| ToolError::ExecutionFailed(format!("Failed to read file: {}", e)))?;

        let data = json!({
            "path": path,
            "content": content,
            "size": content.len()
        });

        Ok(ToolResult::success(data, start.elapsed().as_millis() as u64))
    }
}

/// 🔒 SAFETY: 写文件工具喵
pub struct FsWriteTool {
    workspace: PathBuf,
}

impl FsWriteTool {
    pub fn new(workspace: &Path) -> Self {
        Self {
            workspace: workspace.to_path_buf(),
        }
    }

    fn resolve_path(&self, path: &str) -> Result<PathBuf, ToolError> {
        if path.contains("..") {
            return Err(ToolError::Other("Path traversal detected".to_string()));
        }

        let full_path = self.workspace.join(path);
        let canonical_input = full_path.canonicalize().unwrap_or(full_path.clone());
        let canonical_workspace = self.workspace.canonicalize().unwrap_or(self.workspace.clone());

        if !canonical_input.starts_with(&canonical_workspace) {
            return Err(ToolError::PermissionDenied(
                "Access outside workspace not allowed".to_string(),
            ));
        }

        Ok(full_path)
    }
}

#[async_trait::async_trait]
impl Tool for FsWriteTool {
    fn describe(&self) -> ToolDescription {
        ToolDescription {
            name: "fs_write".to_string(),
            description: "Write content to a file in workspace. Overwrites existing files.".to_string(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "File path relative to workspace"
                    },
                    "content": {
                        "type": "string",
                        "description": "Content to write to the file"
                    }
                },
                "required": ["path", "content"]
            }),
            category: Some("filesystem".to_string()),
            dangerous: true,
            required_permissions: Some(vec!["fs.write".to_string()]),
        }
    }

    fn validate_input(&self, input: &serde_json::Value) -> Result<(), ToolError> {
        if !input.is_object() {
            return Err(ToolError::ValidationError(
                "Input must be a JSON object".to_string(),
            ));
        }

        if input.get("path").is_none() || input.get("content").is_none() {
            return Err(ToolError::ValidationError(
                "Missing required fields: 'path', 'content'".to_string(),
            ));
        }

        Ok(())
    }

    async fn execute(&self, input: serde_json::Value) -> Result<ToolResult, ToolError> {
        let start = std::time::Instant::now();

        let path = input
            .get("path")
            .and_then(|p| p.as_str())
            .ok_or_else(|| ToolError::ValidationError("Invalid 'path' field".to_string()))?;

        let content = input
            .get("content")
            .and_then(|c| c.as_str())
            .ok_or_else(|| ToolError::ValidationError("Invalid 'content' field".to_string()))?;

        let full_path = self.resolve_path(path)?;

        // 确保父目录存在
        if let Some(parent) = full_path.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|e| ToolError::ExecutionFailed(format!("Failed to create directory: {}", e)))?;
        }

        // 写入文件
        tokio::fs::write(&full_path, content)
            .await
            .map_err(|e| ToolError::ExecutionFailed(format!("Failed to write file: {}", e)))?;

        let data = json!({
            "path": path,
            "size": content.len(),
            "status": "written"
        });

        Ok(ToolResult::success(data, start.elapsed().as_millis() as u64))
    }
}
