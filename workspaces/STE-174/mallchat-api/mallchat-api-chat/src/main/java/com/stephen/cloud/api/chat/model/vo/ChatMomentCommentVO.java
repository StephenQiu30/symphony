package com.stephen.cloud.api.chat.model.vo;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Data;

import java.io.Serial;
import java.io.Serializable;
import java.util.Date;
import java.util.List;

/**
 * 动态评论视图
 *
 * @author StephenQiu30
 */
@Data
@Schema(description = "动态评论视图")
public class ChatMomentCommentVO implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    @Schema(description = "评论ID")
    private Long id;

    @Schema(description = "动态ID")
    private Long momentId;

    @Schema(description = "父评论ID（null 为一级评论）")
    private Long parentId;

    @Schema(description = "评论用户ID")
    private Long userId;

    @Schema(description = "用户昵称")
    private String userName;

    @Schema(description = "用户头像")
    private String userAvatar;

    @Schema(description = "评论正文")
    private String content;

    @Schema(description = "子评论列表（二级嵌套）")
    private List<ChatMomentCommentVO> replies;

    @Schema(description = "创建时间")
    private Date createTime;
}
