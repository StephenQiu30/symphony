package com.stephen.cloud.api.chat.model.vo;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Data;

import java.io.Serial;
import java.io.Serializable;
import java.util.Date;

/**
 * 动态点赞视图（含用户基本信息）
 *
 * @author StephenQiu30
 */
@Data
@Schema(description = "动态点赞视图")
public class ChatMomentLikeVO implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    @Schema(description = "点赞ID")
    private Long id;

    @Schema(description = "动态ID")
    private Long momentId;

    @Schema(description = "点赞用户ID")
    private Long userId;

    @Schema(description = "用户昵称")
    private String userName;

    @Schema(description = "用户头像")
    private String userAvatar;

    @Schema(description = "创建时间")
    private Date createTime;
}
