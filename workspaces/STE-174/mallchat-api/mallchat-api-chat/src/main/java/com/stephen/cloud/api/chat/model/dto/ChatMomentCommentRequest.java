package com.stephen.cloud.api.chat.model.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

import java.io.Serial;
import java.io.Serializable;

/**
 * 动态评论请求
 *
 * @author StephenQiu30
 */
@Data
@Schema(description = "动态评论请求")
public class ChatMomentCommentRequest implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    @NotNull(message = "动态ID不能为空")
    @Schema(description = "动态ID", requiredMode = Schema.RequiredMode.REQUIRED)
    private Long momentId;

    @Schema(description = "父评论ID（回复时传入，顶级评论不传）")
    private Long parentId;

    @Schema(description = "评论正文", requiredMode = Schema.RequiredMode.REQUIRED)
    @NotBlank(message = "评论正文不能为空")
    private String content;
}
