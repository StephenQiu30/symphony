package com.stephen.cloud.chat.controller;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.stephen.cloud.api.chat.model.dto.ChatMomentCommentRequest;
import com.stephen.cloud.api.chat.model.dto.ChatMomentCommentQueryRequest;
import com.stephen.cloud.api.chat.model.dto.ChatMomentIdRequest;
import com.stephen.cloud.api.chat.model.dto.ChatMomentPublishRequest;
import com.stephen.cloud.api.chat.model.dto.ChatMomentQueryRequest;
import com.stephen.cloud.api.chat.model.vo.ChatIdVO;
import com.stephen.cloud.api.chat.model.vo.ChatMomentCommentVO;
import com.stephen.cloud.api.chat.model.vo.ChatMomentDetailVO;
import com.stephen.cloud.api.chat.model.vo.ChatMomentVO;
import com.stephen.cloud.api.chat.model.vo.ChatOperationResultVO;
import com.stephen.cloud.chat.service.ChatMomentService;
import com.stephen.cloud.common.auth.utils.SecurityUtils;
import com.stephen.cloud.common.common.BaseResponse;
import com.stephen.cloud.common.common.ErrorCode;
import com.stephen.cloud.common.common.ResultUtils;
import com.stephen.cloud.common.common.ThrowUtils;
import com.stephen.cloud.common.log.annotation.OperationLog;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.annotation.Resource;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 动态接口
 *
 * @author StephenQiu30
 */
@RestController
@RequestMapping("/chat/moment")
@Tag(name = "ChatMomentController", description = "动态管理")
public class ChatMomentController {

    @Resource
    private ChatMomentService chatMomentService;

    @PostMapping("/publish")
    @OperationLog(module = "动态管理", action = "发布动态")
    @Operation(summary = "发布动态", description = "发布文字或图片动态")
    public BaseResponse<ChatIdVO> publish(@Validated @RequestBody ChatMomentPublishRequest request) {
        ThrowUtils.throwIf(request == null, ErrorCode.PARAMS_ERROR);
        Long userId = SecurityUtils.getLoginUserId();
        return ResultUtils.success(ChatIdVO.of(chatMomentService.publish(userId, request)));
    }

    @GetMapping("/list")
    @Operation(summary = "动态列表", description = "查询自己和好友可见动态")
    public BaseResponse<Page<ChatMomentVO>> listVisibleMoments(ChatMomentQueryRequest request) {
        Long userId = SecurityUtils.getLoginUserId();
        return ResultUtils.success(chatMomentService.listVisibleMoments(
                userId, request.getCurrent(), request.getPageSize()));
    }

    @GetMapping("/public/list")
    @Operation(summary = "公开动态广场", description = "分页查询公开且审核通过的动态")
    public BaseResponse<Page<ChatMomentVO>> listPublicMoments(ChatMomentQueryRequest request) {
        Long userId = SecurityUtils.getLoginUserId();
        return ResultUtils.success(chatMomentService.listPublicMoments(
                userId, request.getCurrent(), request.getPageSize()));
    }

    @GetMapping("/detail")
    @Operation(summary = "动态详情", description = "查询单条动态详情（含媒体、点赞、评论）")
    public BaseResponse<ChatMomentDetailVO> getMomentDetail(@Validated ChatMomentIdRequest request) {
        ThrowUtils.throwIf(request == null || request.getId() == null || request.getId() <= 0,
                ErrorCode.PARAMS_ERROR);
        Long userId = SecurityUtils.getLoginUserId();
        return ResultUtils.success(chatMomentService.getMomentDetail(userId, request.getId()));
    }

    @DeleteMapping("/delete")
    @OperationLog(module = "动态管理", action = "删除动态")
    @Operation(summary = "删除动态", description = "删除自己的动态")
    public BaseResponse<ChatOperationResultVO> deleteMoment(@Validated ChatMomentIdRequest request) {
        ThrowUtils.throwIf(request == null || request.getId() == null || request.getId() <= 0,
                ErrorCode.PARAMS_ERROR);
        Long userId = SecurityUtils.getLoginUserId();
        chatMomentService.deleteMoment(userId, request.getId());
        return ResultUtils.success(ChatOperationResultVO.of(true));
    }

    @PostMapping("/like")
    @OperationLog(module = "动态管理", action = "点赞动态")
    @Operation(summary = "点赞动态", description = "点赞自己可见的动态")
    public BaseResponse<ChatOperationResultVO> likeMoment(@Validated ChatMomentIdRequest request) {
        ThrowUtils.throwIf(request == null || request.getId() == null || request.getId() <= 0,
                ErrorCode.PARAMS_ERROR);
        Long userId = SecurityUtils.getLoginUserId();
        chatMomentService.likeMoment(userId, request.getId());
        return ResultUtils.success(ChatOperationResultVO.of(true));
    }

    @DeleteMapping("/like")
    @OperationLog(module = "动态管理", action = "取消点赞动态")
    @Operation(summary = "取消点赞动态", description = "取消点赞自己可见的动态")
    public BaseResponse<ChatOperationResultVO> unlikeMoment(@Validated ChatMomentIdRequest request) {
        ThrowUtils.throwIf(request == null || request.getId() == null || request.getId() <= 0,
                ErrorCode.PARAMS_ERROR);
        Long userId = SecurityUtils.getLoginUserId();
        chatMomentService.unlikeMoment(userId, request.getId());
        return ResultUtils.success(ChatOperationResultVO.of(true));
    }

    @PostMapping("/comment")
    @OperationLog(module = "动态管理", action = "评论动态")
    @Operation(summary = "评论动态", description = "评论自己可见的动态")
    public BaseResponse<ChatIdVO> commentMoment(@Validated @RequestBody ChatMomentCommentRequest request) {
        ThrowUtils.throwIf(request == null, ErrorCode.PARAMS_ERROR);
        Long userId = SecurityUtils.getLoginUserId();
        return ResultUtils.success(ChatIdVO.of(chatMomentService.commentMoment(userId, request)));
    }

    @GetMapping("/comment/list")
    @Operation(summary = "动态评论列表", description = "分页查询自己可见动态的一级评论")
    public BaseResponse<Page<ChatMomentCommentVO>> listComments(@Validated ChatMomentCommentQueryRequest request) {
        ThrowUtils.throwIf(request == null || request.getMomentId() == null || request.getMomentId() <= 0,
                ErrorCode.PARAMS_ERROR);
        Long userId = SecurityUtils.getLoginUserId();
        return ResultUtils.success(chatMomentService.listComments(
                userId, request.getMomentId(), request.getCurrent(), request.getPageSize()));
    }
}
