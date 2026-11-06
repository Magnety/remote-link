//! 文件传输模块：分块、校验、流量控制。

use serde::{Deserialize, Serialize};

#[derive(Debug, thiserror::Error)]
pub enum TransferError {
    #[error("分块数量不匹配: 期望 {0}, 收到 {1}")]
    ChunkCountMismatch(usize, usize),
    #[error("校验和错误")]
    ChecksumMismatch,
    #[error("传输中断")]
    Aborted,
}

/// 文件传输元信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferMeta {
    pub transfer_id: String,
    pub file_name: String,
    pub file_size: u64,
    pub chunk_count: usize,
    pub checksum: String,
    pub direction: TransferDirection,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransferDirection {
    /// 控制端 → 被控端
    ToRemote,
    /// 被控端 → 控制端
    FromRemote,
}

/// 文件分块
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileChunk {
    pub transfer_id: String,
    pub chunk_index: usize,
    pub data: Vec<u8>,
    pub is_final: bool,
}

/// 分块大小 (64KB)
pub const CHUNK_SIZE: usize = 64 * 1024;

/// 文件分块器
pub struct FileSplitter {
    transfer_id: String,
    chunk_index: usize,
}

impl FileSplitter {
    pub fn new(transfer_id: &str) -> Self {
        Self {
            transfer_id: transfer_id.to_string(),
            chunk_index: 0,
        }
    }

    /// 将数据分成块
    pub fn split(data: &[u8]) -> Vec<Vec<u8>> {
        let mut chunks = Vec::new();
        for chunk in data.chunks(CHUNK_SIZE) {
            chunks.push(chunk.to_vec());
        }
        chunks
    }

    pub fn chunk_count(&self, file_size: u64) -> usize {
        if file_size == 0 { return 1; }
        (file_size as usize).div_ceil(CHUNK_SIZE)
    }
}

/// 文件重组器
pub struct FileAssembler {
    meta: TransferMeta,
    chunks: std::collections::HashMap<usize, Vec<u8>>,
}

impl FileAssembler {
    pub fn new(meta: TransferMeta) -> Self {
        Self {
            meta,
            chunks: std::collections::HashMap::new(),
        }
    }

    pub fn add_chunk(&mut self, chunk: &FileChunk) -> Result<bool, TransferError> {
        if chunk.chunk_index >= self.meta.chunk_count {
            return Err(TransferError::ChunkCountMismatch(self.meta.chunk_count, chunk.chunk_index + 1));
        }
        self.chunks.insert(chunk.chunk_index, chunk.data.clone());
        Ok(chunk.is_final)
    }

    pub fn is_complete(&self) -> bool {
        self.chunks.len() == self.meta.chunk_count
    }

    pub fn assemble(&self) -> Result<Vec<u8>, TransferError> {
        if !self.is_complete() {
            return Err(TransferError::ChunkCountMismatch(self.meta.chunk_count, self.chunks.len()));
        }
        let mut data = Vec::with_capacity(self.meta.file_size as usize);
        for i in 0..self.meta.chunk_count {
            if let Some(chunk) = self.chunks.get(&i) {
                data.extend_from_slice(chunk);
            }
        }
        Ok(data)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_file_split_and_assemble() {
        let data: Vec<u8> = (0..100_000u32).map(|i| (i % 256) as u8).collect();
        let chunks = FileSplitter::split(&data);
        assert!(chunks.len() > 1);

        let total: usize = chunks.iter().map(|c| c.len()).sum();
        assert_eq!(total, data.len());

        // 重组
        let mut assembled = Vec::new();
        for chunk in &chunks {
            assembled.extend_from_slice(chunk);
        }
        assert_eq!(assembled, data);
    }

    #[test]
    fn test_assembler() {
        let data = b"hello world remotelink".to_vec();
        let meta = TransferMeta {
            transfer_id: "t-1".into(),
            file_name: "test.txt".into(),
            file_size: data.len() as u64,
            chunk_count: 1,
            checksum: hex::encode(data.clone()),
            direction: TransferDirection::ToRemote,
        };
        let mut assembler = FileAssembler::new(meta);
        assembler.add_chunk(&FileChunk {
            transfer_id: "t-1".into(),
            chunk_index: 0,
            data: data.clone(),
            is_final: true,
        }).unwrap();
        assert!(assembler.is_complete());
        let result = assembler.assemble().unwrap();
        assert_eq!(result, data);
    }
}
