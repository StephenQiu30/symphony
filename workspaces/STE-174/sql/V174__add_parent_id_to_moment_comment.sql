-- STE-174: 动态详情 API — 评论二级嵌套支持
-- 给 chat_moment_comment 表添加 parent_id 字段

ALTER TABLE `chat_moment_comment`
    ADD COLUMN `parent_id` bigint DEFAULT NULL COMMENT '父评论ID（null为一级评论）' AFTER `moment_id`;

-- 优化索引：支持按动态+父评论查询
ALTER TABLE `chat_moment_comment`
    DROP INDEX `idx_moment_time`,
    ADD INDEX `idx_moment_parent_time` (`moment_id`, `parent_id`, `create_time`, `id`);
