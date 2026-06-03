package com.stephen.cloud.chat.model.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableLogic;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.io.Serializable;
import java.util.Date;

/**
 * 动态评论表
 *
 * @author StephenQiu30
 */
@TableName(value = "chat_moment_comment")
@Data
public class ChatMomentComment implements Serializable {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long momentId;

    private Long parentId;

    private Long userId;

    private String content;

    private Integer status;

    private Date createTime;

    private Date updateTime;

    @TableLogic
    private Integer isDelete;

    @TableField(exist = false)
    private static final long serialVersionUID = 1L;
}
