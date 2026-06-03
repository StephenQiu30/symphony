package com.stephen.cloud.api.chat.model.vo;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Data;
import lombok.EqualsAndHashCode;

import java.io.Serial;
import java.util.List;

/**
 * 动态详情视图
 *
 * @author StephenQiu30
 */
@Data
@EqualsAndHashCode(callSuper = true)
@Schema(description = "动态详情视图")
public class ChatMomentDetailVO extends ChatMomentVO {

    @Serial
    private static final long serialVersionUID = 1L;

    @Schema(description = "点赞列表（含用户信息）")
    private List<ChatMomentLikeVO> likeList;

    @Schema(description = "评论列表（二级嵌套）")
    private List<ChatMomentCommentVO> commentList;
}
