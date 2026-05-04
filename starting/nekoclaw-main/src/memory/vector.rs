/*!
 * Simple Vector Database
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15 18:20 JST
 *
 * 功能:
 * - 简化的向量存储 (无需外部依赖)
 * - 余弦相似度计算
 * - KNN 搜索
 */

use std::collections::HashMap;

/// 简化的向量数据库 (内存实现)
pub struct SimpleVectorDB {
    vectors: HashMap<String, Vec<f32>>,
}

impl SimpleVectorDB {
    /// 创建新的向量数据库
    pub fn new() -> Self {
        Self {
            vectors: HashMap::new(),
        }
    }

    /// 添加或更新向量
    pub fn upsert(&mut self, id: &str, vector: Vec<f32>) {
        self.vectors.insert(id.to_string(), vector);
    }

    /// 获取向量
    pub fn get(&self, id: &str) -> Option<&Vec<f32>> {
        self.vectors.get(id)
    }

    /// 删除向量
    pub fn delete(&mut self, id: &str) -> Option<Vec<f32>> {
        self.vectors.remove(id)
    }

    /// 计算余弦相似度
    pub fn cosine_similarity(&self, id_a: &str, id_b: &str) -> Option<f32> {
        let vec_a = self.vectors.get(id_a)?;
        let vec_b = self.vectors.get(id_b)?;
        Some(Self::cosine_similarity_vec(vec_a, vec_b))
    }

    /// 计算向量与查询向量的相似度
    pub fn cosine_similarity_query(&self, query: &[f32], id: &str) -> Option<f32> {
        let vec = self.vectors.get(id)?;
        Some(Self::cosine_similarity_vec(query, vec))
    }

    /// KNN 搜索 (K-Nearest Neighbors)
    pub fn knn_search(&self, query: &[f32], k: usize) -> Vec<(String, f32)> {
        let mut results: Vec<(String, f32)> = self
            .vectors
            .iter()
            .map(|(id, vec)| {
                let similarity = Self::cosine_similarity_vec(query, vec);
                (id.clone(), similarity)
            })
            .collect();

        // 按相似度降序排序
        results.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        // 返回 top-k
        results.into_iter().take(k).collect()
    }

    /// 余弦相似度计算 (静态方法)
    pub fn cosine_similarity_vec(vec_a: &[f32], vec_b: &[f32]) -> f32 {
        if vec_a.is_empty() || vec_b.is_empty() {
            return 0.0;
        }

        let dot: f32 = vec_a.iter().zip(vec_b.iter()).map(|(a, b)| a * b).sum();

        let norm_a: f32 = vec_a.iter().map(|x| x * x).sum::<f32>().sqrt();
        let norm_b: f32 = vec_b.iter().map(|x| x * x).sum::<f32>().sqrt();

        if norm_a == 0.0 || norm_b == 0.0 {
            0.0
        } else {
            dot / (norm_a * norm_b)
        }
    }

    /// 返回向量数量
    pub fn len(&self) -> usize {
        self.vectors.len()
    }

    /// 是否为空
    pub fn is_empty(&self) -> bool {
        self.vectors.is_empty()
    }
}

impl Default for SimpleVectorDB {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cosine_similarity_identical() {
        let vec1 = vec![1.0, 2.0, 3.0];
        let vec2 = vec![1.0, 2.0, 3.0];
        let similarity = SimpleVectorDB::cosine_similarity_vec(&vec1, &vec2);
        assert!((similarity - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_cosine_similarity_orthogonal() {
        let vec1 = vec![1.0, 0.0];
        let vec2 = vec![0.0, 1.0];
        let similarity = SimpleVectorDB::cosine_similarity_vec(&vec1, &vec2);
        assert!((similarity - 0.0).abs() < 0.001);
    }

    #[test]
    fn test_knn_search() {
        let mut db = SimpleVectorDB::new();
        db.upsert("a", vec![1.0, 0.0]);
        db.upsert("b", vec![0.0, 1.0]);
        db.upsert("c", vec![0.5, 0.5]);

        let results = db.knn_search(&[1.0, 0.0], 2);
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].0, "a");
        assert!(results[0].1 > results[1].1);
    }
}
