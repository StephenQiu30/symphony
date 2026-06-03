package com.stephen.cloud.chat.service.impl;

import cn.hutool.core.collection.CollUtil;
import cn.hutool.core.util.StrUtil;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.stephen.cloud.api.chat.model.dto.ChatMomentCommentRequest;
import com.stephen.cloud.api.chat.model.dto.ChatMomentMediaRequest;
import com.stephen.cloud.api.chat.model.dto.ChatMomentPublishRequest;
import com.stephen.cloud.api.chat.model.dto.MomentCreateRequest;
import com.stephen.cloud.api.chat.model.vo.ChatMomentCommentVO;
import com.stephen.cloud.api.chat.model.vo.ChatMomentDetailVO;
import com.stephen.cloud.api.chat.model.vo.ChatMomentLikeVO;
import com.stephen.cloud.api.chat.model.vo.ChatMomentMediaVO;
import com.stephen.cloud.api.chat.model.vo.ChatMomentVO;
import com.stephen.cloud.api.chat.model.vo.MomentVO;
import com.stephen.cloud.api.notification.client.NotificationFeignClient;
import com.stephen.cloud.api.notification.model.dto.NotificationCreateRequest;
import com.stephen.cloud.api.notification.model.enums.NotificationTypeEnum;
import com.stephen.cloud.api.notification.model.vo.NotificationIdVO;
import com.stephen.cloud.api.user.client.UserFeignClient;
import com.stephen.cloud.api.user.model.vo.UserVO;
import com.stephen.cloud.common.common.BaseResponse;
import com.stephen.cloud.chat.mapper.ChatMomentMapper;
import com.stephen.cloud.chat.mapper.ChatMomentCommentMapper;
import com.stephen.cloud.chat.mapper.ChatMomentLikeMapper;
import com.stephen.cloud.chat.mapper.ChatMomentMediaMapper;
import com.stephen.cloud.chat.model.entity.ChatMoment;
import com.stephen.cloud.chat.model.entity.ChatMomentComment;
import com.stephen.cloud.chat.model.entity.ChatMomentLike;
import com.stephen.cloud.chat.model.entity.ChatMomentMedia;
import com.stephen.cloud.chat.service.ChatMomentService;
import com.stephen.cloud.chat.service.UserFriendService;
import com.stephen.cloud.chat.support.ChatBusinessMetricsRecorder;
import com.stephen.cloud.common.common.ErrorCode;
import com.stephen.cloud.common.common.ThrowUtils;
import jakarta.annotation.Resource;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 动态服务实现
 *
 * @author StephenQiu30
 */
@Slf4j
@Service
public class ChatMomentServiceImpl extends ServiceImpl<ChatMomentMapper, ChatMoment>
        implements ChatMomentService {

    private static final int MAX_CONTENT_LENGTH = 1000;
    private static final int MAX_COMMENT_LENGTH = 500;
    private static final int MAX_MEDIA_COUNT = 9;
    private static final int MAX_MEDIA_URL_LENGTH = 1024;
    private static final int DEFAULT_PAGE_SIZE = 10;
    private static final int MAX_PAGE_SIZE = 20;
    private static final int VISIBILITY_FRIEND = 0;
    private static final int VISIBILITY_PUBLIC = 1;
    private static final int AUDIT_STATUS_PASS = 1;
    private static final int STATUS_NORMAL = 0;
    private static final int STATUS_DELETED = 1;
    private static final String RELATED_TYPE_CHAT_MOMENT = "chat_moment";

    @Resource
    private ChatMomentMediaMapper chatMomentMediaMapper;

    @Resource
    private ChatMomentLikeMapper chatMomentLikeMapper;

    @Resource
    private ChatMomentCommentMapper chatMomentCommentMapper;

    @Resource
    private UserFriendService userFriendService;

    @Resource
    private NotificationFeignClient notificationFeignClient;

    @Resource
    private UserFeignClient userFeignClient;

    @Resource
    private ChatBusinessMetricsRecorder businessMetricsRecorder;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public Long publish(Long userId, ChatMomentPublishRequest request) {
        ThrowUtils.throwIf(userId == null || request == null, ErrorCode.PARAMS_ERROR);
        String content = normalizeContent(request.getContent());
        List<ChatMomentMediaRequest> mediaList = normalizeMediaList(request.getMediaList());
        int visibility = normalizeVisibility(request.getVisibility());
        ThrowUtils.throwIf(StrUtil.isBlank(content) && CollUtil.isEmpty(mediaList), ErrorCode.PARAMS_ERROR, "动态内容不能为空");

        ChatMoment moment = new ChatMoment();
        moment.setUserId(userId);
        moment.setContent(content);
        moment.setMediaCount(mediaList.size());
        moment.setLikeCount(0);
        moment.setCommentCount(0);
        moment.setVisibility(visibility);
        moment.setAuditStatus(AUDIT_STATUS_PASS);
        moment.setStatus(STATUS_NORMAL);
        moment.setIsDelete(0);
        boolean saved = saveMoment(moment);
        ThrowUtils.throwIf(!saved || moment.getId() == null, ErrorCode.OPERATION_ERROR, "发布动态失败");

        if (CollUtil.isNotEmpty(mediaList)) {
            boolean mediaSaved = saveMomentMedia(buildMomentMedia(moment.getId(), mediaList));
            ThrowUtils.throwIf(!mediaSaved, ErrorCode.OPERATION_ERROR, "保存动态媒体失败");
        }
        return moment.getId();
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public MomentVO createMoment(Long userId, MomentCreateRequest request) {
        ThrowUtils.throwIf(userId == null || request == null, ErrorCode.PARAMS_ERROR);
        ChatMomentPublishRequest publishRequest = new ChatMomentPublishRequest();
        publishRequest.setContent(request.getContent());
        publishRequest.setVisibility(request.getVisibility() != null ? request.getVisibility() : VISIBILITY_PUBLIC);
        publishRequest.setMediaList(request.getMediaList());
        Long momentId = publish(userId, publishRequest);
        ChatMoment moment = getMomentIncludingDeleted(momentId);
        Map<Long, List<ChatMomentMediaVO>> mediaMap = listMomentMediaMap(List.of(momentId));
        List<ChatMomentMediaVO> mediaVOs = mediaMap.getOrDefault(momentId, Collections.emptyList());
        return toMomentVO(moment, mediaVOs);
    }

    @Override
    public Page<ChatMomentVO> listVisibleMoments(Long userId, int current, int pageSize) {
        ThrowUtils.throwIf(userId == null, ErrorCode.PARAMS_ERROR);
        int normalizedCurrent = current <= 0 ? 1 : current;
        int normalizedPageSize = normalizePageSize(pageSize);
        Set<Long> visibleAuthorIds = new LinkedHashSet<>();
        visibleAuthorIds.add(userId);
        visibleAuthorIds.addAll(listMutualFriendIds(userId));

        Page<ChatMoment> momentPage = pageVisibleMoments(visibleAuthorIds, normalizedCurrent, normalizedPageSize);
        Page<ChatMomentVO> voPage = new Page<>(momentPage.getCurrent(), momentPage.getSize(), momentPage.getTotal());
        if (CollUtil.isEmpty(momentPage.getRecords())) {
            return voPage;
        }
        List<Long> momentIds = momentPage.getRecords().stream().map(ChatMoment::getId).toList();
        Map<Long, List<ChatMomentMediaVO>> mediaMap = listMomentMediaMap(momentIds);
        voPage.setRecords(momentPage.getRecords().stream()
                .map(moment -> toVO(moment, mediaMap.getOrDefault(moment.getId(), Collections.emptyList())))
                .toList());
        return voPage;
    }

    @Override
    public Page<ChatMomentVO> listPublicMoments(Long userId, int current, int pageSize) {
        ThrowUtils.throwIf(userId == null, ErrorCode.PARAMS_ERROR);
        int normalizedCurrent = current <= 0 ? 1 : current;
        int normalizedPageSize = normalizePageSize(pageSize);

        Page<ChatMoment> momentPage = pagePublicMoments(normalizedCurrent, normalizedPageSize);
        List<ChatMoment> visibleRecords = momentPage.getRecords() == null ? Collections.emptyList()
                : momentPage.getRecords().stream()
                .filter(moment -> !isBlockedBetween(userId, moment.getUserId()))
                .toList();
        Page<ChatMomentVO> voPage = new Page<>(momentPage.getCurrent(), momentPage.getSize(), visibleRecords.size());
        if (CollUtil.isEmpty(visibleRecords)) {
            return voPage;
        }
        List<Long> momentIds = visibleRecords.stream().map(ChatMoment::getId).toList();
        Map<Long, List<ChatMomentMediaVO>> mediaMap = listMomentMediaMap(momentIds);
        voPage.setRecords(visibleRecords.stream()
                .map(moment -> toVO(moment, mediaMap.getOrDefault(moment.getId(), Collections.emptyList())))
                .toList());
        return voPage;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void deleteMoment(Long userId, Long momentId) {
        ThrowUtils.throwIf(userId == null || momentId == null || momentId <= 0, ErrorCode.PARAMS_ERROR);
        ChatMoment moment = getMomentIncludingDeleted(momentId);
        ThrowUtils.throwIf(moment == null, ErrorCode.NOT_FOUND_ERROR, "动态不存在");
        ThrowUtils.throwIf(!Objects.equals(userId, moment.getUserId()), ErrorCode.NO_AUTH_ERROR, "无权删除该动态");
        if (Objects.equals(moment.getStatus(), STATUS_DELETED) || Objects.equals(moment.getIsDelete(), 1)) {
            return;
        }
        boolean deleted = softDeleteMoment(momentId);
        ThrowUtils.throwIf(!deleted, ErrorCode.OPERATION_ERROR, "删除动态失败");
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void likeMoment(Long userId, Long momentId) {
        ChatMoment moment = getVisibleActiveMoment(userId, momentId);
        ChatMomentLike existing = getMomentLikeIncludingDeleted(momentId, userId);
        if (existing != null && !Objects.equals(existing.getIsDelete(), 1)) {
            return;
        }
        boolean saved;
        if (existing != null) {
            saved = restoreMomentLike(existing.getId());
        } else {
            ChatMomentLike like = new ChatMomentLike();
            like.setMomentId(momentId);
            like.setUserId(userId);
            like.setIsDelete(0);
            try {
                saved = saveMomentLike(like);
            } catch (DuplicateKeyException e) {
                return;
            }
        }
        if (!saved) {
            return;
        }
        boolean increased = increaseMomentLikeCount(momentId);
        ThrowUtils.throwIf(!increased, ErrorCode.OPERATION_ERROR, "更新点赞数失败");
        businessMetricsRecorder.record("moment_like", "success");
        trySendMomentInteractionNotification(moment, userId, NotificationTypeEnum.LIKE.getCode(), null);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void unlikeMoment(Long userId, Long momentId) {
        getVisibleActiveMoment(userId, momentId);
        ChatMomentLike existing = getMomentLikeIncludingDeleted(momentId, userId);
        if (existing == null || Objects.equals(existing.getIsDelete(), 1)) {
            return;
        }
        boolean deleted = softDeleteMomentLike(existing.getId());
        if (!deleted) {
            return;
        }
        boolean decreased = decreaseMomentLikeCount(momentId);
        ThrowUtils.throwIf(!decreased, ErrorCode.OPERATION_ERROR, "更新点赞数失败");
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public Long commentMoment(Long userId, ChatMomentCommentRequest request) {
        ThrowUtils.throwIf(userId == null || request == null || request.getMomentId() == null
                || request.getMomentId() <= 0, ErrorCode.PARAMS_ERROR);
        String content = normalizeCommentContent(request.getContent());
        ChatMoment moment = getVisibleActiveMoment(userId, request.getMomentId());
        ChatMomentComment comment = new ChatMomentComment();
        comment.setMomentId(request.getMomentId());
        comment.setParentId(request.getParentId());
        comment.setUserId(userId);
        comment.setContent(content);
        comment.setStatus(STATUS_NORMAL);
        comment.setIsDelete(0);
        boolean saved = saveMomentComment(comment);
        ThrowUtils.throwIf(!saved || comment.getId() == null, ErrorCode.OPERATION_ERROR, "评论动态失败");
        boolean increased = increaseMomentCommentCount(request.getMomentId());
        ThrowUtils.throwIf(!increased, ErrorCode.OPERATION_ERROR, "更新评论数失败");
        businessMetricsRecorder.record("moment_comment", "success");
        trySendMomentInteractionNotification(moment, userId, NotificationTypeEnum.COMMENT.getCode(), comment.getId());
        return comment.getId();
    }

    @Override
    public Page<ChatMomentCommentVO> listComments(Long userId, Long momentId, int current, int pageSize) {
        getVisibleActiveMoment(userId, momentId);
        int normalizedCurrent = current <= 0 ? 1 : current;
        int normalizedPageSize = normalizePageSize(pageSize);
        Page<ChatMomentComment> commentPage = pageMomentComments(momentId, normalizedCurrent, normalizedPageSize);
        Page<ChatMomentCommentVO> voPage = new Page<>(commentPage.getCurrent(), commentPage.getSize(), commentPage.getTotal());
        if (CollUtil.isEmpty(commentPage.getRecords())) {
            return voPage;
        }
        voPage.setRecords(commentPage.getRecords().stream().map(this::toCommentVO).toList());
        return voPage;
    }

    @Override
    public ChatMomentDetailVO getMomentDetail(Long userId, Long momentId) {
        ChatMoment moment = getVisibleActiveMoment(userId, momentId);
        List<ChatMomentMediaVO> mediaList = listMomentMediaForDetail(momentId);
        List<ChatMomentLikeVO> likeList = listMomentLikesForDetail(momentId);
        List<ChatMomentCommentVO> allComments = listMomentCommentsForDetail(momentId);
        List<ChatMomentCommentVO> nestedComments = nestComments(allComments);
        return toDetailVO(moment, mediaList, likeList, nestedComments);
    }

    protected boolean saveMoment(ChatMoment moment) {
        return this.save(moment);
    }

    protected boolean saveMomentMedia(List<ChatMomentMedia> mediaList) {
        if (CollUtil.isEmpty(mediaList)) {
            return true;
        }
        for (ChatMomentMedia media : mediaList) {
            if (chatMomentMediaMapper.insert(media) <= 0) {
                return false;
            }
        }
        return true;
    }

    protected Set<Long> listMutualFriendIds(Long userId) {
        return userFriendService.listMutualFriendIds(userId);
    }

    protected Page<ChatMoment> pageVisibleMoments(Set<Long> visibleAuthorIds, int current, int pageSize) {
        if (CollUtil.isEmpty(visibleAuthorIds)) {
            return new Page<>(current, pageSize, 0);
        }
        return this.page(new Page<>(current, pageSize),
                new LambdaQueryWrapper<ChatMoment>()
                        .in(ChatMoment::getUserId, visibleAuthorIds)
                        .eq(ChatMoment::getStatus, STATUS_NORMAL)
                        .eq(ChatMoment::getAuditStatus, AUDIT_STATUS_PASS)
                        .orderByDesc(ChatMoment::getCreateTime)
                        .orderByDesc(ChatMoment::getId));
    }

    protected Page<ChatMoment> pagePublicMoments(int current, int pageSize) {
        return this.page(new Page<>(current, pageSize),
                new LambdaQueryWrapper<ChatMoment>()
                        .eq(ChatMoment::getVisibility, VISIBILITY_PUBLIC)
                        .eq(ChatMoment::getAuditStatus, AUDIT_STATUS_PASS)
                        .eq(ChatMoment::getStatus, STATUS_NORMAL)
                        .orderByDesc(ChatMoment::getLikeCount)
                        .orderByDesc(ChatMoment::getCommentCount)
                        .orderByDesc(ChatMoment::getCreateTime)
                        .orderByDesc(ChatMoment::getId));
    }

    protected boolean isBlockedBetween(Long userId, Long targetUserId) {
        return userFriendService != null && userFriendService.isBlockedBetween(userId, targetUserId);
    }

    protected ChatMoment getMomentIncludingDeleted(Long momentId) {
        return baseMapper.selectByIdIncludingDeleted(momentId);
    }

    protected boolean softDeleteMoment(Long momentId) {
        return this.update(new LambdaUpdateWrapper<ChatMoment>()
                .eq(ChatMoment::getId, momentId)
                .set(ChatMoment::getStatus, STATUS_DELETED)
                .set(ChatMoment::getIsDelete, 1));
    }

    protected ChatMomentLike getMomentLikeIncludingDeleted(Long momentId, Long userId) {
        return chatMomentLikeMapper.selectByMomentIdAndUserIdIncludingDeleted(momentId, userId);
    }

    protected boolean saveMomentLike(ChatMomentLike like) {
        return chatMomentLikeMapper.insert(like) > 0;
    }

    protected boolean restoreMomentLike(Long likeId) {
        return chatMomentLikeMapper.restoreByIdIncludingDeleted(likeId) > 0;
    }

    protected boolean softDeleteMomentLike(Long likeId) {
        return chatMomentLikeMapper.update(null, new LambdaUpdateWrapper<ChatMomentLike>()
                .eq(ChatMomentLike::getId, likeId)
                .set(ChatMomentLike::getIsDelete, 1)) > 0;
    }

    protected boolean increaseMomentLikeCount(Long momentId) {
        return baseMapper.increaseLikeCount(momentId) > 0;
    }

    protected boolean decreaseMomentLikeCount(Long momentId) {
        return baseMapper.decreaseLikeCount(momentId) > 0;
    }

    protected boolean saveMomentComment(ChatMomentComment comment) {
        return chatMomentCommentMapper.insert(comment) > 0;
    }

    protected boolean increaseMomentCommentCount(Long momentId) {
        return baseMapper.increaseCommentCount(momentId) > 0;
    }

    protected Page<ChatMomentComment> pageMomentComments(Long momentId, int current, int pageSize) {
        return chatMomentCommentMapper.selectPage(new Page<>(current, pageSize),
                new LambdaQueryWrapper<ChatMomentComment>()
                        .eq(ChatMomentComment::getMomentId, momentId)
                        .eq(ChatMomentComment::getStatus, STATUS_NORMAL)
                        .orderByAsc(ChatMomentComment::getCreateTime)
                        .orderByAsc(ChatMomentComment::getId));
    }

    protected void sendMomentInteractionNotification(ChatMoment moment, Long actorUserId, String type, Long commentId) {
        NotificationCreateRequest request = new NotificationCreateRequest();
        request.setTitle(NotificationTypeEnum.LIKE.getCode().equals(type) ? "动态点赞" : "动态评论");
        request.setContent(NotificationTypeEnum.LIKE.getCode().equals(type) ? "有人点赞了你的动态" : "有人评论了你的动态");
        request.setType(type);
        request.setUserId(moment.getUserId());
        request.setRelatedId(moment.getId());
        request.setRelatedType(RELATED_TYPE_CHAT_MOMENT);
        request.setContentUrl("/chat/moment/detail?id=" + moment.getId());
        String bizId = NotificationTypeEnum.COMMENT.getCode().equals(type)
                ? "moment_comment_" + commentId
                : "moment_like_" + moment.getId() + "_" + actorUserId;
        request.setBizId(bizId);
        BaseResponse<NotificationIdVO> response = notificationFeignClient.addBusinessNotification(request);
        ThrowUtils.throwIf(response == null || response.getData() == null, ErrorCode.OPERATION_ERROR, "创建互动通知失败");
    }

    protected Map<Long, List<ChatMomentMediaVO>> listMomentMediaMap(List<Long> momentIds) {
        if (CollUtil.isEmpty(momentIds)) {
            return Collections.emptyMap();
        }
        List<ChatMomentMedia> mediaList = chatMomentMediaMapper.selectList(new LambdaQueryWrapper<ChatMomentMedia>()
                .in(ChatMomentMedia::getMomentId, momentIds)
                .orderByAsc(ChatMomentMedia::getMomentId)
                .orderByAsc(ChatMomentMedia::getSortOrder)
                .orderByAsc(ChatMomentMedia::getId));
        if (CollUtil.isEmpty(mediaList)) {
            return Collections.emptyMap();
        }
        return mediaList.stream()
                .map(this::toMediaVO)
                .collect(Collectors.groupingBy(ChatMomentMediaVO::getMomentId));
    }

    protected List<ChatMomentMediaVO> listMomentMediaForDetail(Long momentId) {
        Map<Long, List<ChatMomentMediaVO>> map = listMomentMediaMap(List.of(momentId));
        return map.getOrDefault(momentId, Collections.emptyList());
    }

    protected List<ChatMomentLikeVO> listMomentLikesForDetail(Long momentId) {
        List<ChatMomentLike> likes = chatMomentLikeMapper.selectList(new LambdaQueryWrapper<ChatMomentLike>()
                .eq(ChatMomentLike::getMomentId, momentId)
                .eq(ChatMomentLike::getIsDelete, 0)
                .orderByAsc(ChatMomentLike::getCreateTime)
                .orderByAsc(ChatMomentLike::getId));
        if (CollUtil.isEmpty(likes)) {
            return Collections.emptyList();
        }
        Set<Long> userIds = likes.stream().map(ChatMomentLike::getUserId).collect(Collectors.toSet());
        Map<Long, String[]> userMap = batchGetUserBasicInfo(userIds);
        return likes.stream().map(like -> toLikeVO(like, userMap)).toList();
    }

    protected List<ChatMomentCommentVO> listMomentCommentsForDetail(Long momentId) {
        List<ChatMomentComment> comments = chatMomentCommentMapper.selectList(new LambdaQueryWrapper<ChatMomentComment>()
                .eq(ChatMomentComment::getMomentId, momentId)
                .eq(ChatMomentComment::getStatus, STATUS_NORMAL)
                .eq(ChatMomentComment::getIsDelete, 0)
                .orderByAsc(ChatMomentComment::getCreateTime)
                .orderByAsc(ChatMomentComment::getId));
        if (CollUtil.isEmpty(comments)) {
            return Collections.emptyList();
        }
        Set<Long> userIds = comments.stream().map(ChatMomentComment::getUserId).collect(Collectors.toSet());
        Map<Long, String[]> userMap = batchGetUserBasicInfo(userIds);
        return comments.stream().map(c -> toCommentVOWithUser(c, userMap)).toList();
    }

    protected Map<Long, String[]> batchGetUserBasicInfo(Set<Long> userIds) {
        if (CollUtil.isEmpty(userIds)) {
            return Collections.emptyMap();
        }
        try {
            BaseResponse<List<UserVO>> response = userFeignClient.getUserVOByIds(new ArrayList<>(userIds));
            if (response == null || CollUtil.isEmpty(response.getData())) {
                return Collections.emptyMap();
            }
            return response.getData().stream()
                    .collect(Collectors.toMap(UserVO::getId,
                            u -> new String[]{u.getUserName(), u.getUserAvatar()},
                            (a, b) -> a));
        } catch (Exception e) {
            log.warn("[ChatMomentServiceImpl] 批量获取用户信息失败, userIds: {}, reason: {}",
                    userIds, e.getMessage());
            return Collections.emptyMap();
        }
    }

    private String normalizeContent(String content) {
        if (content == null) {
            return null;
        }
        String normalized = content.trim();
        ThrowUtils.throwIf(normalized.length() > MAX_CONTENT_LENGTH, ErrorCode.PARAMS_ERROR, "动态正文过长");
        return normalized;
    }

    private String normalizeCommentContent(String content) {
        ThrowUtils.throwIf(StrUtil.isBlank(content), ErrorCode.PARAMS_ERROR, "评论内容不能为空");
        String normalized = content.trim();
        ThrowUtils.throwIf(normalized.length() > MAX_COMMENT_LENGTH, ErrorCode.PARAMS_ERROR, "评论内容过长");
        return normalized;
    }

    private List<ChatMomentMediaRequest> normalizeMediaList(List<ChatMomentMediaRequest> mediaList) {
        if (mediaList == null) {
            return Collections.emptyList();
        }
        ThrowUtils.throwIf(mediaList.size() > MAX_MEDIA_COUNT, ErrorCode.PARAMS_ERROR, "动态图片最多 9 张");
        for (ChatMomentMediaRequest media : mediaList) {
            ThrowUtils.throwIf(media == null || StrUtil.isBlank(media.getUrl()), ErrorCode.PARAMS_ERROR, "动态媒体 URL 不能为空");
            String url = media.getUrl().trim();
            ThrowUtils.throwIf(url.length() > MAX_MEDIA_URL_LENGTH, ErrorCode.PARAMS_ERROR, "动态媒体 URL 过长");
            media.setUrl(url);
        }
        return mediaList;
    }

    private List<ChatMomentMedia> buildMomentMedia(Long momentId, List<ChatMomentMediaRequest> mediaRequests) {
        List<ChatMomentMedia> result = new ArrayList<>();
        for (int i = 0; i < mediaRequests.size(); i++) {
            ChatMomentMediaRequest request = mediaRequests.get(i);
            ChatMomentMedia media = new ChatMomentMedia();
            media.setMomentId(momentId);
            media.setUrl(request.getUrl());
            media.setWidth(request.getWidth());
            media.setHeight(request.getHeight());
            media.setSize(request.getSize());
            media.setSortOrder(request.getSortOrder() == null ? i : request.getSortOrder());
            media.setIsDelete(0);
            result.add(media);
        }
        return result;
    }

    private int normalizePageSize(int pageSize) {
        if (pageSize <= 0) {
            return DEFAULT_PAGE_SIZE;
        }
        return Math.min(pageSize, MAX_PAGE_SIZE);
    }

    private int normalizeVisibility(Integer visibility) {
        if (visibility == null) {
            return VISIBILITY_FRIEND;
        }
        ThrowUtils.throwIf(!Objects.equals(visibility, VISIBILITY_FRIEND)
                && !Objects.equals(visibility, VISIBILITY_PUBLIC), ErrorCode.PARAMS_ERROR, "动态可见范围不合法");
        return visibility;
    }

    private ChatMoment getVisibleActiveMoment(Long userId, Long momentId) {
        ThrowUtils.throwIf(userId == null || momentId == null || momentId <= 0, ErrorCode.PARAMS_ERROR);
        ChatMoment moment = getMomentIncludingDeleted(momentId);
        ThrowUtils.throwIf(moment == null || Objects.equals(moment.getStatus(), STATUS_DELETED)
                || Objects.equals(moment.getIsDelete(), 1), ErrorCode.NOT_FOUND_ERROR, "动态不存在");
        ThrowUtils.throwIf(!Objects.equals(moment.getAuditStatus(), AUDIT_STATUS_PASS),
                ErrorCode.NO_AUTH_ERROR, "无权操作该动态");
        if (Objects.equals(userId, moment.getUserId())) {
            return moment;
        }
        ThrowUtils.throwIf(isBlockedBetween(userId, moment.getUserId()),
                ErrorCode.NO_AUTH_ERROR, "无权操作该动态");
        if (Objects.equals(moment.getVisibility(), VISIBILITY_PUBLIC)) {
            return moment;
        }
        Set<Long> friendIds = listMutualFriendIds(userId);
        ThrowUtils.throwIf(CollUtil.isEmpty(friendIds) || !friendIds.contains(moment.getUserId()),
                ErrorCode.NO_AUTH_ERROR, "无权操作该动态");
        return moment;
    }

    private void trySendMomentInteractionNotification(ChatMoment moment, Long actorUserId, String type, Long commentId) {
        if (Objects.equals(moment.getUserId(), actorUserId)) {
            return;
        }
        try {
            sendMomentInteractionNotification(moment, actorUserId, type, commentId);
        } catch (Exception e) {
            log.warn("[ChatMomentServiceImpl] 发送动态互动通知失败, momentId: {}, actorUserId: {}, type: {}, reason: {}",
                    moment.getId(), actorUserId, type, e.getMessage());
        }
    }

    private MomentVO toMomentVO(ChatMoment moment, List<ChatMomentMediaVO> mediaList) {
        MomentVO vo = new MomentVO();
        vo.setId(moment.getId());
        vo.setUserId(moment.getUserId());
        vo.setContent(moment.getContent());
        vo.setMediaCount(moment.getMediaCount());
        vo.setLikeCount(moment.getLikeCount());
        vo.setCommentCount(moment.getCommentCount());
        vo.setVisibility(moment.getVisibility());
        vo.setMediaList(mediaList);
        vo.setCreateTime(moment.getCreateTime());
        return vo;
    }

    private ChatMomentVO toVO(ChatMoment moment, List<ChatMomentMediaVO> mediaList) {
        ChatMomentVO vo = new ChatMomentVO();
        vo.setId(moment.getId());
        vo.setUserId(moment.getUserId());
        vo.setContent(moment.getContent());
        vo.setMediaCount(moment.getMediaCount());
        vo.setLikeCount(moment.getLikeCount());
        vo.setCommentCount(moment.getCommentCount());
        vo.setVisibility(moment.getVisibility());
        vo.setMediaList(mediaList);
        vo.setCreateTime(moment.getCreateTime());
        return vo;
    }

    private ChatMomentMediaVO toMediaVO(ChatMomentMedia media) {
        ChatMomentMediaVO vo = new ChatMomentMediaVO();
        vo.setId(media.getId());
        vo.setMomentId(media.getMomentId());
        vo.setUrl(media.getUrl());
        vo.setWidth(media.getWidth());
        vo.setHeight(media.getHeight());
        vo.setSize(media.getSize());
        vo.setSortOrder(media.getSortOrder());
        return vo;
    }

    private ChatMomentCommentVO toCommentVO(ChatMomentComment comment) {
        ChatMomentCommentVO vo = new ChatMomentCommentVO();
        vo.setId(comment.getId());
        vo.setMomentId(comment.getMomentId());
        vo.setParentId(comment.getParentId());
        vo.setUserId(comment.getUserId());
        vo.setContent(comment.getContent());
        vo.setCreateTime(comment.getCreateTime());
        return vo;
    }

    private ChatMomentDetailVO toDetailVO(ChatMoment moment, List<ChatMomentMediaVO> mediaList,
                                           List<ChatMomentLikeVO> likeList, List<ChatMomentCommentVO> commentList) {
        ChatMomentDetailVO vo = new ChatMomentDetailVO();
        vo.setId(moment.getId());
        vo.setUserId(moment.getUserId());
        vo.setContent(moment.getContent());
        vo.setMediaCount(moment.getMediaCount());
        vo.setLikeCount(moment.getLikeCount());
        vo.setCommentCount(moment.getCommentCount());
        vo.setVisibility(moment.getVisibility());
        vo.setMediaList(mediaList);
        vo.setCreateTime(moment.getCreateTime());
        vo.setLikeList(likeList);
        vo.setCommentList(commentList);
        return vo;
    }

    private ChatMomentLikeVO toLikeVO(ChatMomentLike like, Map<Long, String[]> userMap) {
        ChatMomentLikeVO vo = new ChatMomentLikeVO();
        vo.setId(like.getId());
        vo.setMomentId(like.getMomentId());
        vo.setUserId(like.getUserId());
        vo.setCreateTime(like.getCreateTime());
        String[] userInfo = userMap.get(like.getUserId());
        if (userInfo != null) {
            vo.setUserName(userInfo[0]);
            vo.setUserAvatar(userInfo[1]);
        }
        return vo;
    }

    private ChatMomentCommentVO toCommentVOWithUser(ChatMomentComment comment, Map<Long, String[]> userMap) {
        ChatMomentCommentVO vo = toCommentVO(comment);
        String[] userInfo = userMap.get(comment.getUserId());
        if (userInfo != null) {
            vo.setUserName(userInfo[0]);
            vo.setUserAvatar(userInfo[1]);
        }
        return vo;
    }

    private List<ChatMomentCommentVO> nestComments(List<ChatMomentCommentVO> allComments) {
        if (CollUtil.isEmpty(allComments)) {
            return Collections.emptyList();
        }
        Map<Long, List<ChatMomentCommentVO>> childMap = allComments.stream()
                .filter(c -> c.getParentId() != null)
                .collect(Collectors.groupingBy(ChatMomentCommentVO::getParentId));
        return allComments.stream()
                .filter(c -> c.getParentId() == null)
                .peek(parent -> parent.setReplies(
                        childMap.getOrDefault(parent.getId(), Collections.emptyList())))
                .toList();
    }
}
