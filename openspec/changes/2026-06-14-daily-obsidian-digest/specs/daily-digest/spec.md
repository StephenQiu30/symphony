---
layer: Specs
issue: STE-302
title: "热点日报 Obsidian 知识库 MVP"
status: accepted
---

## S1: 主题入选规则

主题 `T` 进入 `export_date = D`（CST 自然日），当且仅当：

1. `topics.monitor_id = M` 且 `topics.status = 'active'`
2. 存在关联帖，且 `monitor_post_hits.first_seen_at` 或 `platform_posts.published_at` 落入 `[D 00:00 CST, D+1 00:00 CST)`
3. 按 `topics.current_heat_score DESC` 排序，取 Top N（默认 20，由 `DAILY_DIGEST_TOP_N` 配置）

CST 窗口计算 SHALL 使用 `time.FixedZone("CST", 8*3600)` 或 `Asia/Shanghai` 时区。

## S2: Obsidian Frontmatter 契约

每篇 Markdown 笔记 SHALL 包含以下 YAML frontmatter：

```yaml
---
type: hotkey-topic
date: <YYYY-MM-DD>           # export_date，CST 自然日
monitor: <monitor_name>       # keyword_monitors.name
monitor_id: <int64>           # keyword_monitors.id
topic_id: <int64>             # topics.id
topic_key: "<string>"         # topics.topic_key
heat: <float64>               # topics.current_heat_score
trend: <string>               # topics.trend (rising/falling/stable)
post_count: <int>             # 关联帖数量
tags:
  - hotkey
  - topic
  - monitor/<monitor_slug>
---
```

正文 SHALL 包含：
1. LLM 摘要（2–4 段中文）
2. 关键帖摘录（Top 3：作者、摘录、`post_url`）
3. 数据脚注（热度、趋势、帖子数、生成时间）

## S3: Obsidian 文件路径

```
{OBSIDIAN_VAULT_PATH}/HotKey/topics/{monitor-slug}/{date}-topic-{id}-{title-slug}.md
```

- `monitor-slug` SHALL 由 `Slugify(monitor_name)` 生成，去除特殊字符
- `title-slug` SHALL 由 `Slugify(topic_title)` 生成
- 写盘 SHALL 使用原子操作：先写 `*.md.tmp`，再 `os.Rename`

## S4: topic_daily_exports 表契约

```sql
CREATE TABLE topic_daily_exports (
  id BIGSERIAL PRIMARY KEY,
  monitor_id BIGINT NOT NULL REFERENCES keyword_monitors(id),
  topic_id BIGINT NOT NULL REFERENCES topics(id),
  export_date DATE NOT NULL,
  summary_text TEXT NOT NULL DEFAULT '',
  markdown_path TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  error_message TEXT NOT NULL DEFAULT '',
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(monitor_id, topic_id, export_date)
);
```

- `status` SHALL 为 `pending` | `published` | `failed`
- 幂等键：`(monitor_id, topic_id, export_date)`
- Upsert SHALL 使用 `ON CONFLICT (monitor_id, topic_id, export_date) DO UPDATE`

## S5: 配置项契约

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `OBSIDIAN_VAULT_PATH` | — | Vault 同步目录根路径（必填） |
| `DAILY_DIGEST_TIME` | `08:00` | CST 触发时刻 |
| `DAILY_DIGEST_TIMEZONE` | `Asia/Shanghai` | 时区 |
| `DAILY_DIGEST_TARGET` | `yesterday` | `yesterday` \| `today` |
| `DAILY_DIGEST_TOP_N` | `20` | 每 monitor 最多导出主题数 |
| `LLM_PROVIDER` | `openai` | LLM 提供方 |
| `LLM_API_KEY` | — | API Key（启用 LLM 时必填） |
| `LLM_BASE_URL` | `https://api.openai.com/v1` | 兼容网关 |
| `LLM_MODEL` | `gpt-4o-mini` | 模型 |

## S6: LLM 接口契约

```go
type Client interface {
    SummarizeTopic(ctx context.Context, in TopicSummaryInput) (string, error)
}

type TopicSummaryInput struct {
    MonitorName string
    TopicTitle  string
    TopicKey    string
    HeatScore   float64
    Trend       string
    PostCount   int
    Posts       []PostExcerpt  // Top 3，每帖最多 500 字
}
```

- LLM SHALL 生成客观中文摘要，不编造事实
- 输入截断：每帖最多 500 字

## S7: 失败路径

### S7.1: LLM 调用失败

- 单 topic 的 `SummarizeTopic` 返回 error 时，SHALL 将该 topic 的 `topic_daily_exports.status` 设为 `failed`，`error_message` 记录错误信息
- 失败 topic SHALL 不写 Markdown 文件
- 其他 topic SHALL 继续正常处理

### S7.2: Vault 无写权限

- `WriteAtomic` 返回 error 时，SHALL 将该 topic 的 `topic_daily_exports.status` 设为 `failed`
- SHALL 打印错误日志
- 其他 topic SHALL 继续正常处理

### S7.3: 同步盘冲突

- SHALL 使用 `*.md.tmp` → `os.Rename` 原子写入
- 如果 rename 失败，视为 Vault 写入失败（S7.2）

### S7.4: 无热点

- 当天无活跃主题时，SHALL 跳过该 monitor，不写空文件

## S8: 调度契约

- `daily_scheduler` SHALL 每分钟运行（`jobs.Runner` interval 1min）
- 内部判断：当前 CST 时间 ≥ `DAILY_DIGEST_TIME` 且今日 batch 未执行
- 幂等保护：通过查询 `topic_daily_exports` 或 advisory lock 防并发重复
