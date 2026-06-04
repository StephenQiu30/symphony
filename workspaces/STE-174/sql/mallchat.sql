-- ============================================
-- mallchat-cloud 全系统数据库初始化脚本
-- ============================================

-- 1. 创建数据库
CREATE DATABASE IF NOT EXISTS `mallchat` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE `mallchat`;

-- ============================================
-- 2. 用户服务相关表
-- ============================================

-- 用户表
DROP TABLE IF EXISTS `user`;
CREATE TABLE `user`
(
    `id`              bigint       NOT NULL AUTO_INCREMENT COMMENT '用户ID',
    `user_name`       varchar(256)          DEFAULT NULL COMMENT '用户昵称',
    `user_avatar`     varchar(1024)         DEFAULT NULL COMMENT '用户头像',
    `user_profile`    varchar(512)          DEFAULT NULL COMMENT '用户简介',
    `user_role`       varchar(256) NOT NULL DEFAULT 'user' COMMENT '用户角色：user/admin/ban',
    `user_phone`      varchar(128)          DEFAULT NULL COMMENT '用户手机号',
    `user_email`      varchar(256)          DEFAULT NULL COMMENT '用户邮箱',
    `ma_open_id`      varchar(256)          DEFAULT NULL COMMENT '微信小程序 OpenID',
    `wx_union_id`     varchar(256)          DEFAULT NULL COMMENT '微信 UnionID',
    `wx_open_id`      varchar(256)          DEFAULT NULL COMMENT '微信开放平台 OpenID',
    `apple_id`        varchar(256)          DEFAULT NULL COMMENT 'Apple ID',
    `last_login_time` datetime              DEFAULT NULL COMMENT '最后登录时间',
    `last_login_ip`   varchar(128)          DEFAULT NULL COMMENT '最后登录IP',
    `create_time`     datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`     datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`       tinyint      NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    KEY `idx_wx_union_id` (`wx_union_id`),
    KEY `idx_user_phone` (`user_phone`),
    KEY `idx_wx_union_id_is_delete` (`wx_union_id`, `is_delete`),
    KEY `idx_ma_open_id` (`ma_open_id`),
    KEY `idx_wx_open_id` (`wx_open_id`),
    KEY `idx_apple_id` (`apple_id`),
    UNIQUE KEY `uk_user_email` (`user_email`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '用户表';

-- 用户登录日志表
DROP TABLE IF EXISTS `user_login_log`;
CREATE TABLE `user_login_log`
(
    `id`          bigint      NOT NULL AUTO_INCREMENT COMMENT '登录日志ID',
    `user_id`     bigint               DEFAULT NULL COMMENT '用户ID',
    `account`     varchar(256)         DEFAULT NULL COMMENT '登录账号',
    `login_type`  varchar(64)          DEFAULT NULL COMMENT '登录类型',
    `status`      varchar(32) NOT NULL COMMENT '登录状态',
    `fail_reason` varchar(512)         DEFAULT NULL COMMENT '失败原因',
    `client_ip`   varchar(64)          DEFAULT NULL COMMENT '客户端IP',
    `location`    varchar(256)         DEFAULT NULL COMMENT '归属地',
    `user_agent`  varchar(512)         DEFAULT NULL COMMENT 'User-Agent',
    `create_time` datetime    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` datetime    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`   tinyint     NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_account` (`account`),
    KEY `idx_status_create_time` (`status`, `create_time` DESC),
    KEY `idx_client_ip` (`client_ip`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '用户登录日志表';

-- ============================================
-- 3. 日志与存储相关表
-- ============================================

-- 接口访问日志表
DROP TABLE IF EXISTS `api_access_log`;
CREATE TABLE `api_access_log`
(
    `id`            bigint       NOT NULL AUTO_INCREMENT COMMENT '日志ID',
    `trace_id`      varchar(64)           DEFAULT NULL COMMENT '链路追踪ID',
    `user_id`       bigint                DEFAULT NULL COMMENT '用户ID',
    `method`        varchar(16)  NOT NULL COMMENT 'HTTP方法',
    `path`          varchar(512) NOT NULL COMMENT '请求路径',
    `query`         varchar(1024)         DEFAULT NULL COMMENT '查询参数',
    `status`        int                   DEFAULT NULL COMMENT '响应状态码',
    `latency_ms`    int                   DEFAULT NULL COMMENT '耗时毫秒',
    `client_ip`     varchar(64)           DEFAULT NULL COMMENT '客户端IP',
    `user_agent`    varchar(512)          DEFAULT NULL COMMENT 'User-Agent',
    `referer`       varchar(512)          DEFAULT NULL COMMENT 'Referer',
    `request_size`  bigint                DEFAULT NULL COMMENT '请求大小',
    `response_size` bigint                DEFAULT NULL COMMENT '响应大小',
    `create_time`   datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`   datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`     tinyint      NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_path` (`path`(191)),
    KEY `idx_status` (`status`),
    KEY `idx_client_ip` (`client_ip`),
    KEY `idx_create_time` (`create_time`),
    KEY `idx_trace_id` (`trace_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '接口访问日志表';

-- 操作日志表
DROP TABLE IF EXISTS `operation_log`;
CREATE TABLE `operation_log`
(
    `id`              bigint   NOT NULL AUTO_INCREMENT COMMENT '日志ID',
    `operator_id`     bigint            DEFAULT NULL COMMENT '操作人ID',
    `operator_name`   varchar(128)      DEFAULT NULL COMMENT '操作人名称',
    `module`          varchar(64)       DEFAULT NULL COMMENT '模块',
    `action`          varchar(128)      DEFAULT NULL COMMENT '操作类型',
    `biz_id`          varchar(128)      DEFAULT NULL COMMENT '业务ID',
    `method`          varchar(16)       DEFAULT NULL COMMENT 'HTTP方法',
    `path`            varchar(512)      DEFAULT NULL COMMENT '请求路径',
    `request_params`  text COMMENT '请求参数',
    `response_status` int               DEFAULT NULL COMMENT '响应状态码',
    `success`         tinyint  NOT NULL DEFAULT 1 COMMENT '是否成功',
    `error_message`   varchar(1024)     DEFAULT NULL COMMENT '错误信息',
    `client_ip`       varchar(64)       DEFAULT NULL COMMENT '客户端IP',
    `location`        varchar(256)      DEFAULT NULL COMMENT '归属地',
    `user_agent`      varchar(512)      DEFAULT NULL COMMENT '浏览器标识',
    `create_time`     datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`     datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`       tinyint  NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    KEY `idx_operator_id` (`operator_id`),
    KEY `idx_module` (`module`),
    KEY `idx_biz_id` (`biz_id`),
    KEY `idx_success` (`success`),
    KEY `idx_create_time` (`create_time`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '操作日志表';

-- 文件上传记录表
DROP TABLE IF EXISTS `file_upload_record`;
CREATE TABLE `file_upload_record`
(
    `id`            bigint        NOT NULL AUTO_INCREMENT COMMENT '记录ID',
    `user_id`       bigint        NOT NULL COMMENT '上传用户ID',
    `biz_type`      varchar(64)   NOT NULL COMMENT '业务类型',
    `file_name`     varchar(512)  NOT NULL COMMENT '原始文件名',
    `file_size`     bigint        NOT NULL COMMENT '文件大小',
    `file_suffix`   varchar(32)            DEFAULT NULL COMMENT '文件后缀',
    `content_type`  varchar(128)           DEFAULT NULL COMMENT '内容类型',
    `storage_type`  varchar(32)   NOT NULL COMMENT '存储类型',
    `bucket`        varchar(128)           DEFAULT NULL COMMENT '存储桶',
    `object_key`    varchar(512)  NOT NULL COMMENT '对象键/路径',
    `url`           varchar(1024) NOT NULL COMMENT '访问URL',
    `md5`           varchar(64)            DEFAULT NULL COMMENT '文件MD5',
    `client_ip`     varchar(64)            DEFAULT NULL COMMENT '客户端IP',
    `status`        varchar(32)   NOT NULL DEFAULT 'SUCCESS' COMMENT '上传状态',
    `error_message` varchar(1024)          DEFAULT NULL COMMENT '错误信息',
    `create_time`   datetime      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`   datetime      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`     tinyint       NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_biz_type` (`biz_type`),
    KEY `idx_md5` (`md5`),
    KEY `idx_create_time` (`create_time`),
    KEY `idx_storage_type` (`storage_type`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '文件上传记录表';


-- ============================================
-- 4. 业务与消息相关表
-- ============================================

-- 通知表
DROP TABLE IF EXISTS `notification`;
CREATE TABLE `notification`
(
    `id`           bigint       NOT NULL AUTO_INCREMENT COMMENT '通知ID',
    `title`        varchar(256) NOT NULL COMMENT '通知标题',
    `content`      text         NOT NULL COMMENT '通知内容',
    `type`         varchar(64)  NOT NULL COMMENT '通知类型（system-系统通知，user-用户通知，comment-评论通知，like-点赞通知，follow-关注通知，broadcast-全员广播）',
    `biz_id`       varchar(128) NOT NULL DEFAULT '' COMMENT '业务幂等ID',
    `user_id`      bigint       NOT NULL COMMENT '接收用户ID',
    `related_id`   bigint                DEFAULT NULL COMMENT '关联对象ID',
    `related_type` varchar(64)  NOT NULL DEFAULT '' COMMENT '关联对象类型',
    `is_read`      tinyint      NOT NULL DEFAULT 0 COMMENT '是否已读',
    `status`       tinyint      NOT NULL DEFAULT 0 COMMENT '状态（0-正常，1-停用）',
    `content_url`  varchar(512) NOT NULL DEFAULT '' COMMENT '跳转链接',
    `create_time`  datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`  datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`    tinyint      NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_biz_user` (`biz_id`, `user_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_type` (`type`),
    KEY `idx_is_read` (`is_read`),
    KEY `idx_create_time` (`create_time`),
    KEY `idx_user_id_is_read_create_time` (`user_id`, `is_read`, `create_time` DESC)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '通知表';

-- AI 对话记录表
DROP TABLE IF EXISTS `ai_chat_record`;
CREATE TABLE `ai_chat_record`
(
    `id`                bigint   NOT NULL AUTO_INCREMENT COMMENT '对话ID',
    `user_id`           bigint   NOT NULL COMMENT '用户ID',
    `session_id`        varchar(128)      DEFAULT NULL COMMENT '会话ID',
    `message`           text     NOT NULL COMMENT '对话消息',
    `response`          text              DEFAULT NULL COMMENT 'AI响应内容',
    `model_type`        varchar(128)      DEFAULT NULL COMMENT '模型类型',
    `total_tokens`      int               DEFAULT NULL COMMENT '总消耗 token',
    `prompt_tokens`     int               DEFAULT NULL COMMENT '提示消耗 token',
    `completion_tokens` int               DEFAULT NULL COMMENT '生成消耗 token',
    `create_time`       datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`       datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`         tinyint  NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_session_id` (`session_id`),
    KEY `idx_create_time` (`create_time`),
    KEY `idx_user_id_create_time` (`user_id`, `create_time` DESC),
    KEY `idx_session_create` (`session_id`, `create_time` DESC)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = 'AI 对话记录表';

-- ============================================
-- 5. IM / 聊天相关表
-- ============================================

DROP TABLE IF EXISTS `chat_message`;
DROP TABLE IF EXISTS `chat_moment_comment`;
DROP TABLE IF EXISTS `chat_moment_like`;
DROP TABLE IF EXISTS `chat_moment_media`;
DROP TABLE IF EXISTS `chat_moment`;
DROP TABLE IF EXISTS `chat_room_join_apply`;
DROP TABLE IF EXISTS `chat_room_member`;
DROP TABLE IF EXISTS `chat_private_room`;
DROP TABLE IF EXISTS `chat_room`;
DROP TABLE IF EXISTS `chat_report`;
DROP TABLE IF EXISTS `user_friend_block`;
DROP TABLE IF EXISTS `user_friend`;

CREATE TABLE `user_friend`
(
    `id`                bigint   NOT NULL AUTO_INCREMENT COMMENT '主键',
    `user_id`           bigint   NOT NULL COMMENT '用户ID',
    `friend_user_id`    bigint   NOT NULL COMMENT '好友用户ID',
    `remark_name`       varchar(64)      DEFAULT NULL COMMENT '好友备注',
    `friend_group_name` varchar(32)      DEFAULT '默认分组' COMMENT '好友分组名称',
    `create_time`       datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`       datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`         tinyint  NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user_friend` (`user_id`, `friend_user_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_friend_user_id` (`friend_user_id`),
    KEY `idx_user_group` (`user_id`, `friend_group_name`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '用户好友表';

CREATE TABLE `user_friend_block`
(
    `id`              bigint   NOT NULL AUTO_INCREMENT COMMENT '主键',
    `user_id`         bigint   NOT NULL COMMENT '拉黑用户ID',
    `blocked_user_id` bigint   NOT NULL COMMENT '被拉黑用户ID',
    `create_time`     datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`     datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user_blocked` (`user_id`, `blocked_user_id`),
    KEY `idx_blocked_user_id` (`blocked_user_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '用户拉黑关系表';

CREATE TABLE `chat_report`
(
    `id`               bigint       NOT NULL AUTO_INCREMENT COMMENT '举报ID',
    `reporter_user_id` bigint       NOT NULL COMMENT '举报用户ID',
    `target_type`      tinyint      NOT NULL COMMENT '举报对象类型：1-用户，2-消息，3-动态',
    `target_id`        bigint       NOT NULL COMMENT '举报对象ID',
    `target_owner_id`  bigint       NOT NULL COMMENT '被举报对象归属用户ID',
    `reason_type`      varchar(64)  NOT NULL COMMENT '举报原因类型',
    `reason`           varchar(500)          DEFAULT NULL COMMENT '举报说明',
    `status`           tinyint      NOT NULL DEFAULT 0 COMMENT '状态：0-待处理，1-已处理',
    `create_time`      datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`      datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`        tinyint      NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_report_target` (`reporter_user_id`, `target_type`, `target_id`),
    KEY `idx_target_owner` (`target_owner_id`),
    KEY `idx_status_time` (`status`, `create_time`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '聊天举报表';

CREATE TABLE `chat_room`
(
    `id`          bigint      NOT NULL AUTO_INCREMENT COMMENT '房间ID',
    `name`        varchar(64) NOT NULL COMMENT '房间名称',
    `type`        tinyint     NOT NULL DEFAULT 1 COMMENT '房间类型：1-群聊，2-私聊',
    `avatar`      varchar(256)         DEFAULT NULL COMMENT '房间头像',
    `max_members` int                   DEFAULT NULL COMMENT '最大成员数，NULL 或 0 表示不限制',
    `create_user` bigint      NOT NULL COMMENT '创建者用户ID',
    `create_time` datetime    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` datetime    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`   tinyint     NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    KEY `idx_name` (`name`),
    KEY `idx_type` (`type`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '聊天室表';

CREATE TABLE `chat_room_member`
(
    `id`                   bigint   NOT NULL AUTO_INCREMENT COMMENT '成员ID',
    `room_id`              bigint   NOT NULL COMMENT '房间ID',
    `user_id`              bigint   NOT NULL COMMENT '用户ID',
    `role`                 tinyint  NOT NULL DEFAULT 1 COMMENT '角色：1-普通成员，2-管理员，3-群主',
    `last_read_message_id` bigint            DEFAULT NULL COMMENT '最后已读消息ID',
    `create_time`          datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '加入时间',
    `update_time`          datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`            tinyint  NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_room_user` (`room_id`, `user_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_room_id` (`room_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '聊天室成员表';

CREATE TABLE `chat_room_join_apply`
(
    `id`          bigint       NOT NULL AUTO_INCREMENT COMMENT '申请ID',
    `room_id`     bigint       NOT NULL COMMENT '房间ID',
    `user_id`     bigint       NOT NULL COMMENT '申请用户ID',
    `reviewer_id` bigint                DEFAULT NULL COMMENT '审核用户ID',
    `msg`         varchar(256) NOT NULL DEFAULT '' COMMENT '申请留言',
    `review_msg`  varchar(256)          DEFAULT NULL COMMENT '审核留言',
    `status`      tinyint      NOT NULL DEFAULT 1 COMMENT '状态：1-待处理，2-已同意，3-已拒绝',
    `active_key`  varchar(64)           DEFAULT NULL COMMENT '待处理幂等键：roomId:userId',
    `create_time` datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '申请时间',
    `update_time` datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`   tinyint      NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_active_key` (`active_key`),
    KEY `idx_room_status_time` (`room_id`, `status`, `create_time`),
    KEY `idx_user_time` (`user_id`, `create_time`),
    KEY `idx_reviewer_id` (`reviewer_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '入群申请表';

CREATE TABLE `chat_message`
(
    `id`           bigint   NOT NULL AUTO_INCREMENT COMMENT '消息ID',
    `room_id`      bigint   NOT NULL COMMENT '房间ID',
    `from_user_id` bigint   NOT NULL COMMENT '发送者ID',
    `client_msg_id` varchar(64) NOT NULL COMMENT '客户端消息ID',
    `content`      text     NOT NULL COMMENT '消息内容',
    `extra`        json              DEFAULT NULL COMMENT '消息扩展内容（如图片/文件详细信息）',
    `type`         tinyint  NOT NULL DEFAULT 1 COMMENT '消息类型：1-文本，2-图片，3-文件',
    `reply_msg_id` bigint            DEFAULT NULL COMMENT '回复的消息ID',
    `status`       tinyint  NOT NULL DEFAULT 0 COMMENT '消息状态：0-正常，1-已撤回，2-已删除',
    `create_time`  datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '发送时间',
    `update_time`  datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`    tinyint  NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_from_user_client_msg` (`from_user_id`, `client_msg_id`),
    KEY `idx_from_user_id` (`from_user_id`),
    KEY `idx_room_id_id` (`room_id`, `id` DESC),
    KEY `idx_reply_msg_id` (`reply_msg_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '聊天消息表';

CREATE TABLE `chat_moment`
(
    `id`            bigint        NOT NULL AUTO_INCREMENT COMMENT '动态ID',
    `user_id`       bigint        NOT NULL COMMENT '发布用户ID',
    `content`       varchar(1000)          DEFAULT NULL COMMENT '动态正文',
    `media_count`   int           NOT NULL DEFAULT 0 COMMENT '媒体数量',
    `like_count`    int           NOT NULL DEFAULT 0 COMMENT '点赞数',
    `comment_count` int           NOT NULL DEFAULT 0 COMMENT '评论数',
    `visibility`    tinyint       NOT NULL DEFAULT 0 COMMENT '可见范围：0-好友可见，1-公开',
    `audit_status`  tinyint       NOT NULL DEFAULT 1 COMMENT '审核状态：0-待审，1-通过，2-拒绝',
    `status`        tinyint       NOT NULL DEFAULT 0 COMMENT '状态：0-正常，1-已删除',
    `create_time`   datetime      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`   datetime      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`     tinyint       NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    KEY `idx_user_time` (`user_id`, `create_time` DESC),
    KEY `idx_status_time` (`status`, `create_time` DESC),
    KEY `idx_public_rank` (`visibility`, `audit_status`, `status`, `like_count`, `comment_count`, `create_time` DESC, `id` DESC)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '动态主体表';

CREATE TABLE `chat_moment_media`
(
    `id`          bigint        NOT NULL AUTO_INCREMENT COMMENT '动态媒体ID',
    `moment_id`   bigint        NOT NULL COMMENT '动态ID',
    `url`         varchar(1024) NOT NULL COMMENT '媒体URL',
    `width`       int                    DEFAULT NULL COMMENT '图片宽度',
    `height`      int                    DEFAULT NULL COMMENT '图片高度',
    `size`        bigint                 DEFAULT NULL COMMENT '文件大小',
    `sort_order`  int           NOT NULL DEFAULT 0 COMMENT '排序',
    `create_time` datetime      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` datetime      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`   tinyint       NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    KEY `idx_moment_sort` (`moment_id`, `sort_order`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '动态媒体表';

CREATE TABLE `chat_moment_like`
(
    `id`          bigint   NOT NULL AUTO_INCREMENT COMMENT '动态点赞ID',
    `moment_id`   bigint   NOT NULL COMMENT '动态ID',
    `user_id`     bigint   NOT NULL COMMENT '点赞用户ID',
    `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`   tinyint  NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_moment_user` (`moment_id`, `user_id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_moment_id` (`moment_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '动态点赞表';

CREATE TABLE `chat_moment_comment`
(
    `id`          bigint       NOT NULL AUTO_INCREMENT COMMENT '动态评论ID',
    `moment_id`   bigint       NOT NULL COMMENT '动态ID',
    `parent_id`   bigint       DEFAULT NULL COMMENT '父评论ID（null为一级评论）',
    `user_id`     bigint       NOT NULL COMMENT '评论用户ID',
    `content`     varchar(500) NOT NULL COMMENT '评论正文',
    `status`      tinyint      NOT NULL DEFAULT 0 COMMENT '状态：0-正常，1-已删除',
    `create_time` datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`   tinyint      NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    KEY `idx_moment_parent_time` (`moment_id`, `parent_id`, `create_time`, `id`),
    KEY `idx_user_id` (`user_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '动态评论表';

-- 私聊房间映射表
DROP TABLE IF EXISTS `chat_private_room`;
CREATE TABLE `chat_private_room`
(
    `id`          bigint   NOT NULL AUTO_INCREMENT COMMENT '主键',
    `user_low`    bigint   NOT NULL COMMENT '用户ID较小值',
    `user_high`   bigint   NOT NULL COMMENT '用户ID较大值',
    `room_id`     bigint   NOT NULL COMMENT '私聊房间ID',
    `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`   tinyint  NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user_pair` (`user_low`, `user_high`),
    KEY `idx_room_id` (`room_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '私聊房间映射表';

-- 好友申请表
DROP TABLE IF EXISTS `user_friend_apply`;
CREATE TABLE `user_friend_apply`
(
    `id`          bigint       NOT NULL AUTO_INCREMENT COMMENT '申请ID',
    `user_id`     bigint       NOT NULL COMMENT '发起用户ID',
    `target_id`   bigint       NOT NULL COMMENT '目标用户ID',
    `msg`         varchar(256) NOT NULL COMMENT '申请消息',
    `status`      tinyint      NOT NULL DEFAULT 1 COMMENT '状态：1-待处理，2-已同意，3-已忽略',
    `create_time` datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '申请时间',
    `update_time` datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`   tinyint      NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_target_id` (`target_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '好友申请表';

-- 会话列表
DROP TABLE IF EXISTS `chat_session`;
CREATE TABLE `chat_session`
(
    `id`                   bigint   NOT NULL AUTO_INCREMENT COMMENT '主键',
    `user_id`              bigint   NOT NULL COMMENT '所属用户ID',
    `room_id`              bigint   NOT NULL COMMENT '房间ID',
    `last_message_id`      bigint            DEFAULT NULL COMMENT '最后一条消息ID',
    `last_read_message_id` bigint            DEFAULT NULL COMMENT '最后一条已读消息ID',
    `unread_count`         int      NOT NULL DEFAULT 0 COMMENT '未读数',
    `top_status`           tinyint  NOT NULL DEFAULT 0 COMMENT '置顶状态：0-否，1-是',
    `mute_status`          tinyint  NOT NULL DEFAULT 0 COMMENT '免打扰状态：0-否，1-是',
    `active_time`          datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '最后活跃时间（消息发送/变更时间）',
    `create_time`          datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`          datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`            tinyint  NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user_room` (`user_id`, `room_id`),
    KEY `idx_user_id_active` (`user_id`, `active_time` DESC)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '会话列表';

-- 群组详情表
DROP TABLE IF EXISTS `chat_group_info`;
CREATE TABLE `chat_group_info`
(
    `id`           bigint       NOT NULL AUTO_INCREMENT COMMENT '主键',
    `room_id`      bigint       NOT NULL COMMENT '房间ID',
    `group_name`   varchar(128) NOT NULL COMMENT '群聊名称',
    `group_avatar` varchar(512)          DEFAULT NULL COMMENT '群聊头像',
    `announcement` text                  DEFAULT NULL COMMENT '群公告',
    `create_user`  bigint       NOT NULL COMMENT '创建者用户ID',
    `create_time`  datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`  datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `is_delete`    tinyint      NOT NULL DEFAULT 0 COMMENT '是否删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_room_id` (`room_id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '群组详情表';

CREATE TABLE `chat_room_member_audit`
(
    `id`          bigint       NOT NULL AUTO_INCREMENT COMMENT '审计ID',
    `room_id`     bigint       NOT NULL COMMENT '房间ID',
    `user_id`     bigint       NOT NULL COMMENT '被操作用户ID',
    `action`      varchar(32)  NOT NULL COMMENT '操作类型：JOIN/LEAVE/KICK/GRANT_ADMIN/REVOKE_ADMIN',
    `operator_id` bigint       NOT NULL COMMENT '操作人ID',
    `create_time` datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '操作时间',
    PRIMARY KEY (`id`),
    KEY `idx_room_time` (`room_id`, `create_time`),
    KEY `idx_user_time` (`user_id`, `create_time`),
    KEY `idx_action` (`action`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci COMMENT = '群成员变更审计表';
