---
layer: Proposal
issue: STE-302
title: "热点日报 Obsidian 知识库 MVP"
status: accepted
---

## Summary

为 hotkey-server 引入热点日报沉淀能力：按北京时间自然日筛选每个 `keyword_monitor` 的活跃热点主题，调用 LLM 生成中文摘要，渲染为带 YAML frontmatter 的 Markdown 笔记，原子写入 Obsidian 同步目录，并通过 `topic_daily_exports` 表保证幂等、可重试、可审计。

本 change 覆盖 digest 筛选、LLM 摘要、Obsidian 渲染写盘、发布 Job 与调度五层实现。

## In Scope

- `topic_daily_exports` 表 DDL 与 digestrepo CRUD
- Config 扩展：`OBSIDIAN_VAULT_PATH`、`DAILY_DIGEST_TIME`、`DAILY_DIGEST_TIMEZONE`、`DAILY_DIGEST_TARGET`、`DAILY_DIGEST_TOP_N`、`LLM_PROVIDER`、`LLM_API_KEY`、`LLM_BASE_URL`、`LLM_MODEL`
- `internal/digest`：CST 自然日窗口（`DayWindow`）、主题入选规则（Top N by `current_heat_score`）、代表帖聚合
- `internal/llm`：`SummarizeTopic` 接口、OpenAI 兼容实现、prompt 模板、输入截断
- `internal/obsidian`：frontmatter 渲染、slug 生成、`WriteAtomic` 原子写盘
- `internal/jobs/daily_scheduler`：每分钟 gate，判断是否到达 `DAILY_DIGEST_TIME`
- `internal/jobs/publish_daily_topics`：编排 monitors → digest → LLM → export → write
- 单元测试与集成测试覆盖各模块

## Out of Scope

- hotkey-web 配置页、手动触发、预览（后续 Epic）
- Obsidian 官方插件
- 多用户各自 Vault 路径（MVP 全局 `OBSIDIAN_VAULT_PATH`）
- 用户级汇总日报、PDF/邮件推送
- 修改 Jaccard 聚类算法
- OpenAPI 变更
- 生产部署配置

## 与 001 设计的 LLM 范围扩展说明

`docs/design/001-x热点监控平台设计.md` 规定**主题聚合不依赖 LLM**（使用 Jaccard 相似度 + DBSCAN/HDBSCAN 聚类）。本功能作为**独立的日报沉淀层**引入 LLM，定位如下：

- **LLM 仅用于 digest 摘要生成**：为每个已聚类完成的 topic 生成 2–4 段中文摘要，不参与聚类决策
- **聚类逻辑不变**：`internal/topic.Cluster()` 行为不受影响
- **边界清晰**：LLM 调用发生在 `publish_daily_topics` Job 的摘要步骤，输入为已确定的 topic + 代表帖，输出为 `summary_text` 字段
- **可降级**：LLM 失败时单 topic 标记 `status=failed`，不影响其他 topic 的发布

此扩展不改变 001 设计的核心架构，仅在沉淀层新增一个可选的摘要增强步骤。
