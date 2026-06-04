package com.stephen.cloud.chat.service.impl;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.stephen.cloud.api.chat.model.dto.ChatMomentMediaRequest;
import com.stephen.cloud.api.chat.model.dto.ChatMomentCommentRequest;
import com.stephen.cloud.api.chat.model.dto.ChatMomentPublishRequest;
import com.stephen.cloud.api.chat.model.dto.MomentCreateRequest;
import com.stephen.cloud.api.chat.model.vo.ChatMomentCommentVO;
import com.stephen.cloud.api.chat.model.vo.ChatMomentDetailVO;
import com.stephen.cloud.api.chat.model.vo.ChatMomentLikeVO;
import com.stephen.cloud.api.chat.model.vo.ChatMomentVO;
import com.stephen.cloud.api.chat.model.vo.MomentVO;
import com.stephen.cloud.chat.model.entity.ChatMoment;
import com.stephen.cloud.chat.model.entity.ChatMomentComment;
import com.stephen.cloud.chat.model.entity.ChatMomentLike;
import com.stephen.cloud.chat.model.entity.ChatMomentMedia;
import com.stephen.cloud.chat.support.ChatBusinessMetricsRecorder;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.ArrayList;
import java.util.Date;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

class ChatMomentServiceImplTest {

    private TestableChatMomentServiceImpl chatMomentService;
    private SimpleMeterRegistry meterRegistry;

    @BeforeEach
    void setUp() {
        chatMomentService = new TestableChatMomentServiceImpl();
        meterRegistry = new SimpleMeterRegistry();
        ReflectionTestUtils.setField(chatMomentService, "businessMetricsRecorder",
                new ChatBusinessMetricsRecorder(meterRegistry));
    }

    @Test
    void shouldRejectEmptyMoment() {
        ChatMomentPublishRequest request = new ChatMomentPublishRequest();

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.publish(1L, request));
    }

    @Test
    void shouldRejectOverlongContent() {
        ChatMomentPublishRequest request = new ChatMomentPublishRequest();
        request.setContent("a".repeat(1001));

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.publish(1L, request));
    }

    @Test
    void shouldRejectTooManyMediaItems() {
        ChatMomentPublishRequest request = new ChatMomentPublishRequest();
        request.setMediaList(new ArrayList<>());
        for (int i = 0; i < 10; i++) {
            request.getMediaList().add(media("https://example.com/" + i + ".png", i));
        }

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.publish(1L, request));
    }

    @Test
    void shouldRejectBlankMediaUrl() {
        ChatMomentPublishRequest request = new ChatMomentPublishRequest();
        request.setMediaList(List.of(media(" ", 0)));

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.publish(1L, request));
    }

    @Test
    void shouldPublishTextMoment() {
        ChatMomentPublishRequest request = new ChatMomentPublishRequest();
        request.setContent("hello moments");

        Long momentId = chatMomentService.publish(1L, request);

        Assertions.assertEquals(100L, momentId);
        Assertions.assertEquals(1L, chatMomentService.savedMoment.getUserId());
        Assertions.assertEquals("hello moments", chatMomentService.savedMoment.getContent());
        Assertions.assertEquals(0, chatMomentService.savedMoment.getMediaCount());
        Assertions.assertEquals(0, chatMomentService.savedMoment.getVisibility());
        Assertions.assertEquals(1, chatMomentService.savedMoment.getAuditStatus());
        Assertions.assertTrue(chatMomentService.savedMediaList.isEmpty());
    }

    @Test
    void shouldPublishPublicMomentWithAuditPass() {
        ChatMomentPublishRequest request = new ChatMomentPublishRequest();
        request.setContent("public moment");
        request.setVisibility(1);

        Long momentId = chatMomentService.publish(1L, request);

        Assertions.assertEquals(100L, momentId);
        Assertions.assertEquals(1, chatMomentService.savedMoment.getVisibility());
        Assertions.assertEquals(1, chatMomentService.savedMoment.getAuditStatus());
    }

    @Test
    void shouldRejectInvalidMomentVisibility() {
        ChatMomentPublishRequest request = new ChatMomentPublishRequest();
        request.setContent("bad visibility");
        request.setVisibility(9);

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.publish(1L, request));
    }

    @Test
    void shouldPublishImageMomentWithMediaOrder() {
        ChatMomentPublishRequest request = new ChatMomentPublishRequest();
        request.setContent("with images");
        request.setMediaList(List.of(
                media("https://example.com/1.png", 0),
                media("https://example.com/2.png", 1)));

        Long momentId = chatMomentService.publish(1L, request);

        Assertions.assertEquals(100L, momentId);
        Assertions.assertEquals(2, chatMomentService.savedMoment.getMediaCount());
        Assertions.assertEquals(2, chatMomentService.savedMediaList.size());
        Assertions.assertEquals(100L, chatMomentService.savedMediaList.get(0).getMomentId());
        Assertions.assertEquals("https://example.com/1.png", chatMomentService.savedMediaList.get(0).getUrl());
        Assertions.assertEquals(0, chatMomentService.savedMediaList.get(0).getSortOrder());
        Assertions.assertEquals(1, chatMomentService.savedMediaList.get(1).getSortOrder());
    }

    @Test
    void shouldListOwnAndFriendMoments() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.moments = List.of(
                moment(10L, 1L, "mine"),
                moment(11L, 2L, "friend"));

        Page<ChatMomentVO> page = chatMomentService.listVisibleMoments(1L, 1, 10);

        Assertions.assertEquals(new LinkedHashSet<>(Set.of(1L, 2L)), chatMomentService.capturedVisibleAuthorIds);
        Assertions.assertEquals(2, page.getRecords().size());
        Assertions.assertEquals(10L, page.getRecords().get(0).getId());
        Assertions.assertEquals(11L, page.getRecords().get(1).getId());
    }

    @Test
    void shouldFilterStrangerMomentsBeforePagination() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>();
        chatMomentService.moments = List.of(
                moment(10L, 2L, "stranger"),
                moment(11L, 1L, "mine"));

        Page<ChatMomentVO> page = chatMomentService.listVisibleMoments(1L, 1, 10);

        Assertions.assertEquals(new LinkedHashSet<>(Set.of(1L)), chatMomentService.capturedVisibleAuthorIds);
        Assertions.assertEquals(1, page.getRecords().size());
        Assertions.assertEquals(11L, page.getRecords().get(0).getId());
    }

    @Test
    void shouldListPublicMomentsByLightRanking() {
        ChatMoment friendOnly = moment(10L, 2L, "friend only");
        ChatMoment rejected = publicMoment(11L, 3L, "rejected", 8, 6);
        rejected.setAuditStatus(2);
        ChatMoment olderPopular = publicMoment(12L, 4L, "older popular", 5, 3);
        ChatMoment newerPopular = publicMoment(13L, 5L, "newer popular", 5, 3);
        ChatMoment latestQuiet = publicMoment(14L, 6L, "latest quiet", 0, 0);
        chatMomentService.moments = List.of(friendOnly, rejected, olderPopular, newerPopular, latestQuiet);

        Page<ChatMomentVO> page = chatMomentService.listPublicMoments(1L, 1, 10);

        Assertions.assertEquals(3, page.getRecords().size());
        Assertions.assertEquals(13L, page.getRecords().get(0).getId());
        Assertions.assertEquals(12L, page.getRecords().get(1).getId());
        Assertions.assertEquals(14L, page.getRecords().get(2).getId());
        Assertions.assertEquals(1, page.getRecords().get(0).getVisibility());
    }

    @Test
    void shouldExcludeBlockedAuthorFromPublicMomentsAndInteraction() {
        chatMomentService.blockedUserIds = Set.of(2L);
        chatMomentService.moments = List.of(
                publicMoment(10L, 2L, "blocked public", 9, 9),
                publicMoment(11L, 3L, "visible public", 1, 1));
        chatMomentService.momentById = Map.of(10L, chatMomentService.moments.get(0));

        Page<ChatMomentVO> page = chatMomentService.listPublicMoments(1L, 1, 10);

        Assertions.assertEquals(1, page.getRecords().size());
        Assertions.assertEquals(11L, page.getRecords().get(0).getId());
        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.likeMoment(1L, 10L));
        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.commentMoment(1L, commentRequest(10L, "blocked")));
        Assertions.assertTrue(chatMomentService.savedLikes.isEmpty());
        Assertions.assertTrue(chatMomentService.savedComments.isEmpty());
    }

    @Test
    void shouldDeleteOwnMoment() {
        ChatMoment moment = moment(10L, 1L, "mine");
        chatMomentService.momentById = Map.of(10L, moment);

        chatMomentService.deleteMoment(1L, 10L);

        Assertions.assertEquals(List.of(10L), chatMomentService.deletedMomentIds);
    }

    @Test
    void shouldKeepRepeatedDeleteByAuthorIdempotent() {
        ChatMoment deletedMoment = moment(10L, 1L, "mine");
        deletedMoment.setStatus(1);
        deletedMoment.setIsDelete(1);
        chatMomentService.momentById = Map.of(10L, deletedMoment);

        chatMomentService.deleteMoment(1L, 10L);

        Assertions.assertTrue(chatMomentService.deletedMomentIds.isEmpty());
    }

    @Test
    void shouldRejectDeleteOtherUserMoment() {
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "friend"));

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.deleteMoment(1L, 10L));
    }

    @Test
    void shouldRejectMissingMomentDelete() {
        chatMomentService.momentById = Map.of();

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.deleteMoment(1L, 10L));
    }

    @Test
    void shouldLikeVisibleMomentAndCreateNotification() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "friend"));

        chatMomentService.likeMoment(1L, 10L);

        Assertions.assertEquals(1, chatMomentService.savedLikes.size());
        Assertions.assertEquals(10L, chatMomentService.savedLikes.get(0).getMomentId());
        Assertions.assertEquals(1L, chatMomentService.savedLikes.get(0).getUserId());
        Assertions.assertEquals(List.of(10L), chatMomentService.likeIncrementMomentIds);
        Assertions.assertEquals(List.of("like:10:2:1"), chatMomentService.sentNotifications);
        Assertions.assertEquals(1.0, businessCounter("moment_like", "success"));
    }

    @Test
    void shouldKeepRepeatedLikeIdempotent() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "friend"));
        chatMomentService.likeByMomentAndUser = Map.of("10:1", activeLike(31L, 10L, 1L));

        chatMomentService.likeMoment(1L, 10L);

        Assertions.assertTrue(chatMomentService.savedLikes.isEmpty());
        Assertions.assertTrue(chatMomentService.likeIncrementMomentIds.isEmpty());
        Assertions.assertTrue(chatMomentService.sentNotifications.isEmpty());
    }

    @Test
    void shouldTreatDuplicateLikeInsertAsIdempotent() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "friend"));
        chatMomentService.duplicateLikeOnSave = true;

        chatMomentService.likeMoment(1L, 10L);

        Assertions.assertTrue(chatMomentService.likeIncrementMomentIds.isEmpty());
        Assertions.assertTrue(chatMomentService.sentNotifications.isEmpty());
    }

    @Test
    void shouldUnlikeLikedMomentAndDecreaseCount() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "friend"));
        chatMomentService.likeByMomentAndUser = Map.of("10:1", activeLike(31L, 10L, 1L));

        chatMomentService.unlikeMoment(1L, 10L);

        Assertions.assertEquals(List.of(31L), chatMomentService.deletedLikeIds);
        Assertions.assertEquals(List.of(10L), chatMomentService.likeDecreaseMomentIds);
    }

    @Test
    void shouldKeepRepeatedUnlikeIdempotent() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "friend"));

        chatMomentService.unlikeMoment(1L, 10L);

        Assertions.assertTrue(chatMomentService.deletedLikeIds.isEmpty());
        Assertions.assertTrue(chatMomentService.likeDecreaseMomentIds.isEmpty());
    }

    @Test
    void shouldRejectInvisibleMomentInteraction() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>();
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "stranger"));

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.likeMoment(1L, 10L));
        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.commentMoment(1L, commentRequest(10L, "hi")));
        Assertions.assertTrue(chatMomentService.savedLikes.isEmpty());
        Assertions.assertTrue(chatMomentService.savedComments.isEmpty());
    }

    @Test
    void shouldAllowPublicMomentInteractionWithoutFriendRelation() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>();
        chatMomentService.momentById = Map.of(10L, publicMoment(10L, 2L, "public", 0, 0));

        chatMomentService.likeMoment(1L, 10L);
        Long commentId = chatMomentService.commentMoment(1L, commentRequest(10L, "nice"));

        Assertions.assertEquals(200L, commentId);
        Assertions.assertEquals(1, chatMomentService.savedLikes.size());
        Assertions.assertEquals(1, chatMomentService.savedComments.size());
    }

    @Test
    void shouldRejectAuditFailedMomentInteraction() {
        ChatMoment rejected = publicMoment(10L, 2L, "rejected", 0, 0);
        rejected.setAuditStatus(2);
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.momentById = Map.of(10L, rejected);

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.likeMoment(1L, 10L));
        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.commentMoment(1L, commentRequest(10L, "hi")));
        Assertions.assertTrue(chatMomentService.savedLikes.isEmpty());
        Assertions.assertTrue(chatMomentService.savedComments.isEmpty());
    }

    @Test
    void shouldRejectMissingOrDeletedMomentInteraction() {
        ChatMoment deletedMoment = moment(10L, 2L, "deleted");
        deletedMoment.setStatus(1);
        deletedMoment.setIsDelete(1);
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.momentById = Map.of(10L, deletedMoment);

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.likeMoment(1L, 99L));
        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.likeMoment(1L, 10L));
        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.commentMoment(1L, commentRequest(10L, "hi")));
        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.listComments(1L, 10L, 1, 10));
        Assertions.assertTrue(chatMomentService.savedLikes.isEmpty());
        Assertions.assertTrue(chatMomentService.savedComments.isEmpty());
        Assertions.assertTrue(chatMomentService.sentNotifications.isEmpty());
    }

    @Test
    void shouldRejectInvalidCommentContent() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "friend"));

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.commentMoment(1L, commentRequest(10L, " ")));
        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.commentMoment(1L, commentRequest(10L, "a".repeat(501))));
    }

    @Test
    void shouldCommentVisibleMomentAndCreateNotification() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "friend"));

        Long commentId = chatMomentService.commentMoment(1L, commentRequest(10L, " hello "));

        Assertions.assertEquals(200L, commentId);
        Assertions.assertEquals(1, chatMomentService.savedComments.size());
        Assertions.assertEquals(10L, chatMomentService.savedComments.get(0).getMomentId());
        Assertions.assertEquals(1L, chatMomentService.savedComments.get(0).getUserId());
        Assertions.assertEquals("hello", chatMomentService.savedComments.get(0).getContent());
        Assertions.assertEquals(List.of(10L), chatMomentService.commentIncrementMomentIds);
        Assertions.assertEquals(List.of("comment:10:2:1"), chatMomentService.sentNotifications);
        Assertions.assertEquals(1.0, businessCounter("moment_comment", "success"));
    }

    @Test
    void shouldListVisibleMomentComments() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "friend"));
        chatMomentService.comments = List.of(comment(101L, 10L, 2L, "first"), comment(102L, 10L, 3L, "second"));

        Page<ChatMomentCommentVO> page = chatMomentService.listComments(1L, 10L, 1, 10);

        Assertions.assertEquals(2, page.getRecords().size());
        Assertions.assertEquals(101L, page.getRecords().get(0).getId());
        Assertions.assertEquals("first", page.getRecords().get(0).getContent());
    }

    @Test
    void shouldRejectInvisibleMomentCommentList() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>();
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "stranger"));

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.listComments(1L, 10L, 1, 10));
    }

    @Test
    void shouldFilterDeletedCommentsInList() {
        ChatMomentComment deletedComment = comment(102L, 10L, 3L, "deleted");
        deletedComment.setIsDelete(1);
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "friend"));
        chatMomentService.comments = List.of(comment(101L, 10L, 2L, "first"), deletedComment);

        Page<ChatMomentCommentVO> page = chatMomentService.listComments(1L, 10L, 1, 10);

        Assertions.assertEquals(1, page.getRecords().size());
        Assertions.assertEquals(101L, page.getRecords().get(0).getId());
    }

    @Test
    void shouldKeepInteractionWhenNotificationFails() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "friend"));
        chatMomentService.failNotification = true;

        chatMomentService.likeMoment(1L, 10L);
        Long commentId = chatMomentService.commentMoment(1L, commentRequest(10L, "still saved"));

        Assertions.assertEquals(200L, commentId);
        Assertions.assertEquals(1, chatMomentService.savedLikes.size());
        Assertions.assertEquals(1, chatMomentService.savedComments.size());
        Assertions.assertEquals(List.of(10L), chatMomentService.likeIncrementMomentIds);
        Assertions.assertEquals(List.of(10L), chatMomentService.commentIncrementMomentIds);
        Assertions.assertEquals(1.0, businessCounter("moment_like", "success"));
        Assertions.assertEquals(1.0, businessCounter("moment_comment", "success"));
    }

    @Test
    void shouldNotNotifyWhenInteractingWithOwnMoment() {
        chatMomentService.momentById = Map.of(10L, moment(10L, 1L, "mine"));

        chatMomentService.likeMoment(1L, 10L);
        chatMomentService.commentMoment(1L, commentRequest(10L, "mine"));

        Assertions.assertEquals(1, chatMomentService.savedLikes.size());
        Assertions.assertEquals(1, chatMomentService.savedComments.size());
        Assertions.assertTrue(chatMomentService.sentNotifications.isEmpty());
    }

    // --- createMoment tests (STE-170) ---

    @Test
    void shouldCreateTextMomentWithDefaultPublicVisibility() {
        MomentCreateRequest request = new MomentCreateRequest();
        request.setContent("hello from createMoment");

        MomentVO vo = chatMomentService.createMoment(1L, request);

        Assertions.assertNotNull(vo);
        Assertions.assertEquals(100L, vo.getId());
        Assertions.assertEquals(1L, vo.getUserId());
        Assertions.assertEquals("hello from createMoment", vo.getContent());
        Assertions.assertEquals(0, vo.getMediaCount());
        Assertions.assertEquals(0, vo.getLikeCount());
        Assertions.assertEquals(0, vo.getCommentCount());
        Assertions.assertEquals(1, vo.getVisibility());
        Assertions.assertNotNull(vo.getMediaList());
        Assertions.assertTrue(vo.getMediaList().isEmpty());
    }

    @Test
    void shouldCreateMomentWithExplicitFriendVisibility() {
        MomentCreateRequest request = new MomentCreateRequest();
        request.setContent("friend only");
        request.setVisibility(0);

        MomentVO vo = chatMomentService.createMoment(1L, request);

        Assertions.assertEquals(0, vo.getVisibility());
    }

    @Test
    void shouldCreateImageMomentWithMedia() {
        MomentCreateRequest request = new MomentCreateRequest();
        request.setContent("with images");
        request.setMediaList(List.of(
                media("https://example.com/a.png", 0),
                media("https://example.com/b.png", 1)));

        MomentVO vo = chatMomentService.createMoment(1L, request);

        Assertions.assertEquals(2, vo.getMediaCount());
        Assertions.assertEquals(2, vo.getMediaList().size());
        Assertions.assertEquals("https://example.com/a.png", vo.getMediaList().get(0).getUrl());
        Assertions.assertEquals("https://example.com/b.png", vo.getMediaList().get(1).getUrl());
        Assertions.assertEquals(1, vo.getVisibility());
    }

    @Test
    void shouldRejectEmptyCreateMomentRequest() {
        MomentCreateRequest request = new MomentCreateRequest();

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.createMoment(1L, request));
    }

    // --- getMomentDetail tests (STE-174) ---

    @Test
    void shouldReturnFullDetailForOwnMoment() {
        ChatMoment myMoment = moment(10L, 1L, "my detail");
        myMoment.setMediaCount(2);
        myMoment.setLikeCount(1);
        myMoment.setCommentCount(1);
        chatMomentService.momentById = Map.of(10L, myMoment);
        chatMomentService.detailMediaList = List.of(
                chatMomentMediaVO(1L, 10L, "https://example.com/1.png", 0),
                chatMomentMediaVO(2L, 10L, "https://example.com/2.png", 1));
        chatMomentService.detailLikes = List.of(
                likeVO(31L, 10L, 2L, "Alice", "https://avatar/a.png"));
        chatMomentService.detailComments = List.of(
                commentVO(101L, 10L, null, 2L, "Bob", "https://avatar/b.png", "nice"));

        ChatMomentDetailVO detail = chatMomentService.getMomentDetail(1L, 10L);

        Assertions.assertNotNull(detail);
        Assertions.assertEquals(10L, detail.getId());
        Assertions.assertEquals(1L, detail.getUserId());
        Assertions.assertEquals("my detail", detail.getContent());
        Assertions.assertEquals(2, detail.getMediaList().size());
        Assertions.assertEquals(1, detail.getLikeList().size());
        Assertions.assertEquals("Alice", detail.getLikeList().get(0).getUserName());
        Assertions.assertEquals("https://avatar/a.png", detail.getLikeList().get(0).getUserAvatar());
        Assertions.assertEquals(1, detail.getCommentList().size());
        Assertions.assertEquals("Bob", detail.getCommentList().get(0).getUserName());
    }

    @Test
    void shouldReturnDetailForVisibleFriendMoment() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        ChatMoment friendMoment = moment(11L, 2L, "friend detail");
        chatMomentService.momentById = Map.of(11L, friendMoment);

        ChatMomentDetailVO detail = chatMomentService.getMomentDetail(1L, 11L);

        Assertions.assertNotNull(detail);
        Assertions.assertEquals(11L, detail.getId());
        Assertions.assertEquals(2L, detail.getUserId());
    }

    @Test
    void shouldReturnDetailForPublicMomentWithoutFriendRelation() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>();
        ChatMoment publicMmt = publicMoment(12L, 3L, "public detail", 5, 2);
        chatMomentService.momentById = Map.of(12L, publicMmt);

        ChatMomentDetailVO detail = chatMomentService.getMomentDetail(1L, 12L);

        Assertions.assertNotNull(detail);
        Assertions.assertEquals(12L, detail.getId());
    }

    @Test
    void shouldReturn404ForInvisibleStrangerMoment() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>();
        ChatMoment strangerMoment = moment(10L, 2L, "stranger");
        chatMomentService.momentById = Map.of(10L, strangerMoment);

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.getMomentDetail(1L, 10L));
    }

    @Test
    void shouldReturn404ForDeletedMoment() {
        ChatMoment deletedMoment = moment(10L, 2L, "deleted");
        deletedMoment.setStatus(1);
        deletedMoment.setIsDelete(1);
        chatMomentService.momentById = Map.of(10L, deletedMoment);

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.getMomentDetail(1L, 10L));
    }

    @Test
    void shouldReturn404ForNonexistentMoment() {
        chatMomentService.momentById = Map.of();

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.getMomentDetail(1L, 999L));
    }

    @Test
    void shouldReturn404ForAuditFailedMoment() {
        ChatMoment rejected = publicMoment(10L, 2L, "rejected", 0, 0);
        rejected.setAuditStatus(2);
        chatMomentService.momentById = Map.of(10L, rejected);

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.getMomentDetail(1L, 10L));
    }

    @Test
    void shouldReturn404ForBlockedAuthorMoment() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        chatMomentService.blockedUserIds = Set.of(2L);
        chatMomentService.momentById = Map.of(10L, moment(10L, 2L, "blocked"));

        Assertions.assertThrows(RuntimeException.class, () -> chatMomentService.getMomentDetail(1L, 10L));
    }

    @Test
    void shouldNestChildCommentsUnderParent() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        ChatMoment mmt = moment(10L, 2L, "with nested comments");
        chatMomentService.momentById = Map.of(10L, mmt);
        chatMomentService.detailComments = List.of(
                commentVO(101L, 10L, null, 2L, "Alice", "https://avatar/a.png", "top level"),
                commentVO(102L, 10L, 101L, 3L, "Bob", "https://avatar/b.png", "reply to Alice"),
                commentVO(103L, 10L, 101L, 4L, "Carol", "https://avatar/c.png", "another reply"),
                commentVO(104L, 10L, null, 5L, "Dave", "https://avatar/d.png", "another top level"));

        ChatMomentDetailVO detail = chatMomentService.getMomentDetail(1L, 10L);

        Assertions.assertEquals(2, detail.getCommentList().size());
        Assertions.assertEquals(101L, detail.getCommentList().get(0).getId());
        Assertions.assertNull(detail.getCommentList().get(0).getParentId());
        Assertions.assertEquals(2, detail.getCommentList().get(0).getReplies().size());
        Assertions.assertEquals(102L, detail.getCommentList().get(0).getReplies().get(0).getId());
        Assertions.assertEquals(101L, detail.getCommentList().get(0).getReplies().get(0).getParentId());
        Assertions.assertEquals("Bob", detail.getCommentList().get(0).getReplies().get(0).getUserName());
        Assertions.assertEquals(104L, detail.getCommentList().get(1).getId());
        Assertions.assertTrue(detail.getCommentList().get(1).getReplies().isEmpty());
    }

    @Test
    void shouldIncludeUserBasicInfoInLikes() {
        chatMomentService.visibleFriendIds = new LinkedHashSet<>(Set.of(2L));
        ChatMoment mmt = moment(10L, 2L, "with likes");
        chatMomentService.momentById = Map.of(10L, mmt);
        chatMomentService.detailLikes = List.of(
                likeVO(31L, 10L, 3L, "Alice", "https://avatar/a.png"),
                likeVO(32L, 10L, 4L, "Bob", null));

        ChatMomentDetailVO detail = chatMomentService.getMomentDetail(1L, 10L);

        Assertions.assertEquals(2, detail.getLikeList().size());
        Assertions.assertEquals(3L, detail.getLikeList().get(0).getUserId());
        Assertions.assertEquals("Alice", detail.getLikeList().get(0).getUserName());
        Assertions.assertEquals("https://avatar/a.png", detail.getLikeList().get(0).getUserAvatar());
        Assertions.assertEquals(4L, detail.getLikeList().get(1).getUserId());
        Assertions.assertEquals("Bob", detail.getLikeList().get(1).getUserName());
        Assertions.assertNull(detail.getLikeList().get(1).getUserAvatar());
    }

    private static ChatMomentMediaRequest media(String url, int sortOrder) {
        ChatMomentMediaRequest request = new ChatMomentMediaRequest();
        request.setUrl(url);
        request.setWidth(100);
        request.setHeight(80);
        request.setSize(1024L);
        request.setSortOrder(sortOrder);
        return request;
    }

    private static ChatMoment moment(Long id, Long userId, String content) {
        ChatMoment moment = new ChatMoment();
        moment.setId(id);
        moment.setUserId(userId);
        moment.setContent(content);
        moment.setMediaCount(0);
        moment.setLikeCount(0);
        moment.setCommentCount(0);
        moment.setStatus(0);
        moment.setVisibility(0);
        moment.setAuditStatus(1);
        moment.setIsDelete(0);
        moment.setCreateTime(new Date(id));
        return moment;
    }

    private static ChatMoment publicMoment(Long id, Long userId, String content, int likeCount, int commentCount) {
        ChatMoment moment = moment(id, userId, content);
        moment.setVisibility(1);
        moment.setLikeCount(likeCount);
        moment.setCommentCount(commentCount);
        return moment;
    }

    private static ChatMomentLike activeLike(Long id, Long momentId, Long userId) {
        ChatMomentLike like = new ChatMomentLike();
        like.setId(id);
        like.setMomentId(momentId);
        like.setUserId(userId);
        like.setIsDelete(0);
        return like;
    }

    private static ChatMomentComment comment(Long id, Long momentId, Long userId, String content) {
        return commentWithParent(id, momentId, null, userId, content);
    }

    private static ChatMomentComment commentWithParent(Long id, Long momentId, Long parentId, Long userId, String content) {
        ChatMomentComment comment = new ChatMomentComment();
        comment.setId(id);
        comment.setMomentId(momentId);
        comment.setParentId(parentId);
        comment.setUserId(userId);
        comment.setContent(content);
        comment.setIsDelete(0);
        comment.setCreateTime(new Date(id));
        return comment;
    }

    private static com.stephen.cloud.api.chat.model.vo.ChatMomentMediaVO chatMomentMediaVO(
            Long id, Long momentId, String url, int sortOrder) {
        com.stephen.cloud.api.chat.model.vo.ChatMomentMediaVO vo = new com.stephen.cloud.api.chat.model.vo.ChatMomentMediaVO();
        vo.setId(id);
        vo.setMomentId(momentId);
        vo.setUrl(url);
        vo.setWidth(100);
        vo.setHeight(80);
        vo.setSize(1024L);
        vo.setSortOrder(sortOrder);
        return vo;
    }

    private static ChatMomentLikeVO likeVO(Long id, Long momentId, Long userId, String userName, String userAvatar) {
        ChatMomentLikeVO vo = new ChatMomentLikeVO();
        vo.setId(id);
        vo.setMomentId(momentId);
        vo.setUserId(userId);
        vo.setUserName(userName);
        vo.setUserAvatar(userAvatar);
        vo.setCreateTime(new Date(id));
        return vo;
    }

    private static ChatMomentCommentVO commentVO(Long id, Long momentId, Long parentId, Long userId,
                                                  String userName, String userAvatar, String content) {
        ChatMomentCommentVO vo = new ChatMomentCommentVO();
        vo.setId(id);
        vo.setMomentId(momentId);
        vo.setParentId(parentId);
        vo.setUserId(userId);
        vo.setUserName(userName);
        vo.setUserAvatar(userAvatar);
        vo.setContent(content);
        vo.setCreateTime(new Date(id));
        return vo;
    }

    private static ChatMomentCommentRequest commentRequest(Long momentId, String content) {
        ChatMomentCommentRequest request = new ChatMomentCommentRequest();
        request.setMomentId(momentId);
        request.setContent(content);
        return request;
    }

    private double businessCounter(String action, String result) {
        return meterRegistry.get("mallchat.im.business.total")
                .tag("action", action)
                .tag("result", result)
                .counter()
                .count();
    }

    private static class TestableChatMomentServiceImpl extends ChatMomentServiceImpl {
        private ChatMoment savedMoment;
        private final List<ChatMomentMedia> savedMediaList = new ArrayList<>();
        private List<ChatMoment> moments = new ArrayList<>();
        private Set<Long> visibleFriendIds = new LinkedHashSet<>();
        private Set<Long> blockedUserIds = Set.of();
        private Set<Long> capturedVisibleAuthorIds = new LinkedHashSet<>();
        private Map<Long, ChatMoment> momentById = Map.of();
        private final List<Long> deletedMomentIds = new ArrayList<>();
        private Map<String, ChatMomentLike> likeByMomentAndUser = Map.of();
        private final List<ChatMomentLike> savedLikes = new ArrayList<>();
        private final List<Long> restoredLikeIds = new ArrayList<>();
        private final List<Long> deletedLikeIds = new ArrayList<>();
        private final List<Long> likeIncrementMomentIds = new ArrayList<>();
        private final List<Long> likeDecreaseMomentIds = new ArrayList<>();
        private final List<ChatMomentComment> savedComments = new ArrayList<>();
        private final List<Long> commentIncrementMomentIds = new ArrayList<>();
        private List<ChatMomentComment> comments = new ArrayList<>();
        private List<com.stephen.cloud.api.chat.model.vo.ChatMomentMediaVO> detailMediaList = List.of();
        private List<ChatMomentLikeVO> detailLikes = List.of();
        private List<ChatMomentCommentVO> detailComments = List.of();
        private final List<String> sentNotifications = new ArrayList<>();
        private boolean failNotification;
        private boolean duplicateLikeOnSave;

        @Override
        protected boolean saveMoment(ChatMoment moment) {
            moment.setId(100L);
            this.savedMoment = moment;
            // Auto-register so getMomentIncludingDeleted works in createMoment flow
            Map<Long, ChatMoment> updated = new java.util.HashMap<>(momentById);
            updated.put(100L, moment);
            momentById = updated;
            return true;
        }

        @Override
        protected boolean saveMomentMedia(List<ChatMomentMedia> mediaList) {
            this.savedMediaList.clear();
            this.savedMediaList.addAll(mediaList);
            return true;
        }

        @Override
        protected Set<Long> listMutualFriendIds(Long userId) {
            return new LinkedHashSet<>(visibleFriendIds);
        }

        @Override
        protected boolean isBlockedBetween(Long userId, Long targetUserId) {
            return blockedUserIds.contains(targetUserId);
        }

        @Override
        protected Page<ChatMoment> pageVisibleMoments(Set<Long> visibleAuthorIds, int current, int pageSize) {
            capturedVisibleAuthorIds = new LinkedHashSet<>(visibleAuthorIds);
            List<ChatMoment> records = moments.stream()
                    .filter(item -> visibleAuthorIds.contains(item.getUserId()))
                    .filter(item -> Integer.valueOf(0).equals(item.getStatus()))
                    .filter(item -> Integer.valueOf(1).equals(item.getAuditStatus()))
                    .filter(item -> Integer.valueOf(0).equals(item.getIsDelete()))
                    .toList();
            Page<ChatMoment> page = new Page<>(current, pageSize, records.size());
            page.setRecords(records);
            return page;
        }

        @Override
        protected Page<ChatMoment> pagePublicMoments(int current, int pageSize) {
            List<ChatMoment> records = moments.stream()
                    .filter(item -> Integer.valueOf(1).equals(item.getVisibility()))
                    .filter(item -> Integer.valueOf(1).equals(item.getAuditStatus()))
                    .filter(item -> Integer.valueOf(0).equals(item.getStatus()))
                    .filter(item -> Integer.valueOf(0).equals(item.getIsDelete()))
                    .sorted((left, right) -> {
                        int likeCompare = Integer.compare(right.getLikeCount(), left.getLikeCount());
                        if (likeCompare != 0) {
                            return likeCompare;
                        }
                        int commentCompare = Integer.compare(right.getCommentCount(), left.getCommentCount());
                        if (commentCompare != 0) {
                            return commentCompare;
                        }
                        int timeCompare = right.getCreateTime().compareTo(left.getCreateTime());
                        if (timeCompare != 0) {
                            return timeCompare;
                        }
                        return Long.compare(right.getId(), left.getId());
                    })
                    .toList();
            Page<ChatMoment> page = new Page<>(current, pageSize, records.size());
            page.setRecords(records);
            return page;
        }

        @Override
        protected Map<Long, List<com.stephen.cloud.api.chat.model.vo.ChatMomentMediaVO>> listMomentMediaMap(List<Long> momentIds) {
            if (savedMediaList.isEmpty()) {
                return Map.of();
            }
            // Build media VO map from saved media for createMoment flow
            Map<Long, List<com.stephen.cloud.api.chat.model.vo.ChatMomentMediaVO>> result = new java.util.HashMap<>();
            for (Long momentId : momentIds) {
                List<com.stephen.cloud.api.chat.model.vo.ChatMomentMediaVO> vos = savedMediaList.stream()
                        .filter(m -> momentId.equals(m.getMomentId()))
                        .map(m -> {
                            com.stephen.cloud.api.chat.model.vo.ChatMomentMediaVO vo = new com.stephen.cloud.api.chat.model.vo.ChatMomentMediaVO();
                            vo.setId(m.getId() != null ? m.getId() : 1L);
                            vo.setMomentId(m.getMomentId());
                            vo.setUrl(m.getUrl());
                            vo.setWidth(m.getWidth());
                            vo.setHeight(m.getHeight());
                            vo.setSize(m.getSize());
                            vo.setSortOrder(m.getSortOrder());
                            return vo;
                        })
                        .toList();
                if (!vos.isEmpty()) {
                    result.put(momentId, vos);
                }
            }
            return result;
        }

        @Override
        protected ChatMoment getMomentIncludingDeleted(Long momentId) {
            return momentById.get(momentId);
        }

        @Override
        protected boolean softDeleteMoment(Long momentId) {
            deletedMomentIds.add(momentId);
            return true;
        }

        @Override
        protected ChatMomentLike getMomentLikeIncludingDeleted(Long momentId, Long userId) {
            return likeByMomentAndUser.get(momentId + ":" + userId);
        }

        @Override
        protected boolean saveMomentLike(ChatMomentLike like) {
            if (duplicateLikeOnSave) {
                throw new DuplicateKeyException("duplicate moment like");
            }
            savedLikes.add(like);
            return true;
        }

        @Override
        protected boolean restoreMomentLike(Long likeId) {
            restoredLikeIds.add(likeId);
            return true;
        }

        @Override
        protected boolean softDeleteMomentLike(Long likeId) {
            deletedLikeIds.add(likeId);
            return true;
        }

        @Override
        protected boolean increaseMomentLikeCount(Long momentId) {
            likeIncrementMomentIds.add(momentId);
            return true;
        }

        @Override
        protected boolean decreaseMomentLikeCount(Long momentId) {
            likeDecreaseMomentIds.add(momentId);
            return true;
        }

        @Override
        protected boolean saveMomentComment(ChatMomentComment comment) {
            comment.setId(200L);
            savedComments.add(comment);
            return true;
        }

        @Override
        protected boolean increaseMomentCommentCount(Long momentId) {
            commentIncrementMomentIds.add(momentId);
            return true;
        }

        @Override
        protected Page<ChatMomentComment> pageMomentComments(Long momentId, int current, int pageSize) {
            List<ChatMomentComment> records = comments.stream()
                    .filter(item -> momentId.equals(item.getMomentId()))
                    .filter(item -> Integer.valueOf(0).equals(item.getIsDelete()))
                    .toList();
            Page<ChatMomentComment> page = new Page<>(current, pageSize, records.size());
            page.setRecords(records);
            return page;
        }

        @Override
        protected void sendMomentInteractionNotification(ChatMoment moment, Long actorUserId, String type, Long commentId) {
            if (failNotification) {
                throw new RuntimeException("notification down");
            }
            sentNotifications.add(type + ":" + moment.getId() + ":" + moment.getUserId() + ":" + actorUserId);
        }

        @Override
        protected List<ChatMomentLikeVO> listMomentLikesForDetail(Long momentId) {
            return detailLikes;
        }

        @Override
        protected List<ChatMomentCommentVO> listMomentCommentsForDetail(Long momentId) {
            return detailComments;
        }

        @Override
        protected List<com.stephen.cloud.api.chat.model.vo.ChatMomentMediaVO> listMomentMediaForDetail(Long momentId) {
            return detailMediaList;
        }
    }
}
