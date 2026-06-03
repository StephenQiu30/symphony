package com.stephen.cloud.chat.service;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.IService;
import com.stephen.cloud.api.chat.model.dto.ChatMomentCommentRequest;
import com.stephen.cloud.api.chat.model.dto.ChatMomentPublishRequest;
import com.stephen.cloud.api.chat.model.dto.MomentCreateRequest;
import com.stephen.cloud.api.chat.model.vo.ChatMomentCommentVO;
import com.stephen.cloud.api.chat.model.vo.ChatMomentDetailVO;
import com.stephen.cloud.api.chat.model.vo.ChatMomentVO;
import com.stephen.cloud.api.chat.model.vo.MomentVO;
import com.stephen.cloud.chat.model.entity.ChatMoment;

/**
 * 动态服务
 *
 * @author StephenQiu30
 */
public interface ChatMomentService extends IService<ChatMoment> {

    Long publish(Long userId, ChatMomentPublishRequest request);

    MomentVO createMoment(Long userId, MomentCreateRequest request);

    Page<ChatMomentVO> listVisibleMoments(Long userId, int current, int pageSize);

    Page<ChatMomentVO> listPublicMoments(Long userId, int current, int pageSize);

    void deleteMoment(Long userId, Long momentId);

    void likeMoment(Long userId, Long momentId);

    void unlikeMoment(Long userId, Long momentId);

    Long commentMoment(Long userId, ChatMomentCommentRequest request);

    Page<ChatMomentCommentVO> listComments(Long userId, Long momentId, int current, int pageSize);

    ChatMomentDetailVO getMomentDetail(Long userId, Long momentId);
}
