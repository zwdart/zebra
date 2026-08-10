# 局域网聊天室功能设计方案

> 状态:**已评审确认** · 日期:2026-08-10
> 范围:在现有 LAN 单聊基础上**新增聊天室**,单聊功能完整保留、行为不变。
> 已确认决策:架构=**方案 A 房主星型**;聊天室内文件=v1 不做(走单聊);
> 历史消息=v1 不同步(新成员只看到加入后的消息)。

## 1. 目标与约束

- **新增**"聊天室":局域网内多台设备加入同一房间进行群聊(文本)。
- **完整保留**现有单人聊天:不修改 `ChatServer` / `ChatClient` 的单聊路径与帧协议兼容性。
- **无中心服务器**:纯局域网 P2P,设备即开即用,不引入任何外网依赖。
- **最大化复用**:UDP 心跳发现、'J'/'G' 帧协议、sqlite 持久化、消息气泡 UI、连接收敛逻辑。
- 稳定性优先:房间功能与单聊**风险隔离**(独立端口、独立组件、独立状态)。

## 2. 现有架构要点(实现依据)

| 层 | 现状 |
|---|---|
| 发现 | UDP 广播 + 组播 `239.255.0.250`,端口 19422,每 3s 心跳,负载 `{deviceId,name,port}` |
| 传输 | 每设备一个 TCP 服务器(22066 起 20 个候选端口),一对一连接;双方同时互连时按 id 收敛为单连接 |
| 帧协议 | `'J'` 标记 + 4 字节长度 + UTF-8 JSON;`'G'` 标记文件块(自带 transferId,并发多文件) |
| 消息类型 | `hello / text / system / file_meta / file_ready / file_cancel / file_done / file_error` |
| 持久化 | sqlite:`chat_messages`(peer_id 为会话键)+ `chat_peers`(会话列表/未读数) |
| 状态管理 | `ChatProvider`(单例):`ChatServer` + 每设备一个 `ChatClient`,消息按 peerId 归档 |
| UI | 首页 Tab「设备 / 会话」+ `ChatScreen` 私聊页;`MessageBubble` 消息气泡可复用 |

关键实现细节(设计须延续的既有约定):

1. 帧解析必须**容错**:恶意/损坏帧 try-catch 隔离,不能取消 socket 监听(已有先例)。
2. 大流量下必须**分批让出事件循环**(`kMaxFramesPerBatch`),避免主 isolate 被占满卡死 UI。
3. 发送/接收均有**背压**机制(pause/resume + 批量 flush),房间转发同样适用。
4. 设备 ID 全局唯一(uuid),作为成员身份标识与去重依据。
5. 真实 TCP 端口随心跳广播(默认端口被占时回退候选端口),消费方以心跳里的 port 为准。

## 3. 候选架构方案对比

| 维度 | A. 房主星型(推荐) | B. 全互联 mesh | C. UDP 广播聊天 |
|---|---|---|---|
| 拓扑 | 一人建房为房主,成员直连房主,房主转发 | 每成员与所有其他成员互联,各自广播 | 直接复用 UDP 组播/广播通道 |
| 实现复杂度 | 低-中 | 高 | 低 |
| 消息可靠性 | TCP 可靠,房主统一转发 | TCP 可靠,但各端顺序不一致 | UDP 不可靠(丢包/乱序) |
| 消息顺序 | 房主串行转发,全房间一致 | 无全局顺序,各端不同 | 天然乱序,需序号+缓冲 |
| 单点故障 | 房主离线=房间解散(v1) | 无单点,任意设备离线不影响 | 无单点 |
| 成员管理 | 房主集中维护,简单可靠 | 需 gossip 同步成员列表,复杂 | 无状态,需要额外在线探测 |
| 文件传输 | 可经房主转发,或成员点对点 | 每对成员直传,复杂度平方级 | 不适合(UDP 无可靠大包) |
| 复用现有代码 | 高:帧协议/持久化/UI 气泡/心跳发现全部复用 | 低:推翻单连接模型,与收敛逻辑冲突 | 中:复用 UDP 通道,但消息层全新 |
| 对单聊的侵入 | 最小:独立端口+独立组件 | 大:连接管理共享,牵一发动全身 | 小:另开消息通道 |
| 适合场景 | 家庭/办公室 10~50 人 | 需要无中心的强健性 | 极简玩具级、容忍丢消息 |

**推荐方案 A**:局域网聊天室的现实需求是"房主建个房,大家进来聊",星型拓扑
实现量最小、消息顺序天然一致、成员管理简单,且与现有单聊完全隔离,符合
"单聊完整保留"的硬约束。方案 B 的复杂度与收益在局域网规模下不成比例;
方案 C 不可靠,聊天体验无法保证,仅作技术对比项。

下文全部按方案 A 展开。

---

## 4. 方案 A 详细设计(房主星型)

### 4.1 总体架构

- 每个设备**同时**运行:
  - 现有 `ChatServer`(单聊 TCP,22066 起)——**不动**;
  - 新增 `RoomHost`(房主房间 TCP,**独立端口 22088 起**,候选策略同单聊);
  - 新增 `RoomClient`(作为成员连接某房主,复用现有 `ChatClient` 的建连/帧解析模式)。
- 一台设备可以既是**房主**(运行 RoomHost),又是**成员**(RoomClient 连别人的房间),互不干扰。
- 房主把房间摘要随心跳广播:`{room: {id, name, memberCount, hostName}}`,
  非房主设备在「附近房间」列表看到该房间,点击即加入。
- 身份标识:`deviceId`(uuid)即成员 ID,房间内消息的 `senderId` 沿用设备 ID,与单聊一致。

### 4.2 协议设计

复用现有 `'J'` JSON 帧(`0x4A + 4字节长度 + JSON`),新增房间帧类型,帧格式完全兼容:

| 帧类型 | 方向 | 载荷 | 说明 |
|---|---|---|---|
| `room_join` | 成员→房主 | `{roomId, senderId, senderName}` | 申请加入 |
| `room_join_ack` | 房主→成员 | `{roomId, roomName, hostId, hostName, members:[{deviceId,deviceName}]}` | 加入成功+当前成员列表 |
| `room_join_reject` | 房主→成员 | `{roomId, reason: full/not_found}` | 房间满/不存在 |
| `room_members` | 房主→全体 | `{roomId, action: joined/left, member:{deviceId,deviceName}, members:[...]}` | 成员变化广播(增量+全量,便于同步) |
| `room_msg` | 成员→房主→其他成员 | `{roomId, msgId, senderId, senderName, content, timestamp}` | 文本消息,房主**转发给除发送者外所有成员** |
| `room_leave` | 成员→房主 | `{roomId, senderId}` | 主动离开 |
| `room_close` | 房主→全体 | `{roomId}` | 房主解散房间 |
| `room_error` | 房主→成员 | `{roomId, code, message}` | 一般错误(心跳/转发失败提示) |

设计要点:

1. **帧格式零改动**:沿用 `kJsonMarker` + TLV,房间帧只是 `type` 字段多了 `room_*`,
   旧版本客户端收到未知类型走 `default` 分支仅打日志,不会崩溃——天然向后兼容。
2. **消息转发**:房主收到 `room_msg` 后**原样转发**(不重新生成 id),保证全房间 `msgId` 一致,
   接收端按 `msgId` 去重(重连/重发场景防重复显示)。
3. **成员表由房主持有权威版本**,每次变化广播 `room_members`(含全量列表),
   成员端无需自建发现协议,弱网/丢帧也能靠下一次全量自愈。
4. **无历史同步(v1)**:新成员只拿到"加入时刻起的消息",历史同步列为后续增强(见 §7)。
5. **消息大小限制**:单条 `room_msg` 限制 64KB(与单聊一致,防恶意大帧刷爆房主转发)。

### 4.3 数据模型

```dart
/// 房间成员(房主侧持有 socket,成员侧仅展示信息)
class RoomMember {
  final String deviceId;
  String deviceName;
  Socket? socket;        // 房主侧才有:用于转发
  DateTime joinedAt;
}

/// 房间(房主侧)
class ChatRoom {
  final String roomId;          // uuid
  String name;
  final String hostId;
  String hostName;
  final int port;               // 房主 RoomHost 实际监听端口
  final List<RoomMember> members;
  DateTime createdAt;
}

/// 房间消息 —— 直接复用 ChatMessage,新增 roomId 字段即可
class RoomChatMessage extends ChatMessage {
  final String roomId;
}
```

持久化:复用现有 `chat_messages` 表,`peer_id` 用 `'room:<roomId>'` 前缀作为会话键,
`ChatRepository` 的存取/分页/已读/删除**全部复用,零新增 SQL**。

### 4.4 组件划分(新增文件)

```
lib/features/lan_chat/
  models/room.dart                 // ChatRoom / RoomMember
  models/room_chat_message.dart    // RoomChatMessage(或并入 room.dart)
  services/room_host.dart          // 房主房间服务器:监听、成员管理、转发
  services/room_client.dart        // 成员侧房间客户端(建连/收发,参考 ChatClient)
  providers/room_provider.dart     // 房间状态管理(ChangeNotifier,与 ChatProvider 平级)
  screens/room_list_screen.dart    // 房间列表页(我的房间+附近房间)
  screens/room_screen.dart         // 聊天室会话页
  widgets/room_member_bar.dart     // 成员横条(头像/名字)
  widgets/room_tile.dart           // 房间条目
```

接入点:

- `LanDiscoveryService._sendHeartbeat()`:房主时追加 `room` 摘要字段;
  `LanDiscoveryService` 新增 `setRoomInfo(...)` / `clearRoomInfo()`。
- 首页 `LanChatHomeScreen`:Tab 从 2 个扩展为 3 个「设备 / 会话 / 聊天室」。
- `main.dart` / 各 Provider 注册处:新增 `RoomProvider` 单例。

### 4.5 关键技术点

1. **转发背压**:房主向多成员转发时,成员 socket 慢会积压内存。
   复用单聊的批量 flush 思路(`kChunksPerFlush`);文本消息小,单条转发开销可忽略,
   但转发循环内仍每 16 条让出一次事件循环(沿用 `kMaxFramesPerBatch` 思想)。
2. **断线检测**:房主侧监听成员 socket `onDone/onError` → 从成员表移除并广播
   `room_members(left)`;成员侧监听 `RoomClient` 断开 → 提示"房主已离线",
   房间标记为已解散并回到列表页。
3. **去重**:接收端按 `msgId` 去重(内存 Set,房间消息数有限,无需落库去重)。
4. **单连接模型冲突规避**:房间通道与单聊通道端口独立,互不影响;
   成员与房主之间**只有一条房间 TCP 连接**(不建立单聊连接),不触发
   `_convergeSingleConnection`,与单聊完全解耦。
5. **安全**:沿用既有容错约定——帧解析 try-catch、恶意帧跳过不杀连接;
   转发前校验 `senderId ∈ members`(防伪冒);房间人数上限默认 **50**,可配。
6. **文件传输**:v1 聊天室**仅文本+系统消息**;文件仍走现有单聊(点成员头像
   发起私聊/发文件)。聊天室内文件转发列为后续增强(§7)。

### 4.6 稳定性与风险

| 风险 | 对策 |
|---|---|
| 房主离线,房间解散 | v1 明确此语义,成员端友好提示;房主迁移列为后续增强 |
| 转发积压拖垮房主 | 消息大小 64KB 上限 + 人数上限 50 + 批量 flush/让出事件循环 |
| 端口冲突(22088 起被占) | 与单聊相同的候选端口策略(20 个连续端口,真实端口随心跳广播) |
| 新成员加入瞬间消息丢失 | v1 接受(无历史同步);`room_join_ack` 含全量成员表,保证成员列表自愈 |
| 对单聊的回归风险 | 单聊代码零修改;房间全部新增文件;联调时跑单聊回归用例 |
| 多设备同时建房 | 房间以房主 deviceId 区分,`roomId` 全局唯一,无冲突 |

---

## 5. UI 业务流程

### 5.1 页面结构与导航

```
首页 LanChatHomeScreen(TabController length: 3)
├─ Tab1 设备(现有,不动)
├─ Tab2 会话(现有,不动)
└─ Tab3 聊天室(新增 RoomListScreen)
      ├─ 「我的房间」卡片区
      │     ├─ 未建房:  [创建房间] 按钮 → 输入房间名 → 建房成功
      │     └─ 已建房:  房间名/成员数/在线成员 → [进入] [解散]
      ├─ 「附近房间」列表区(来自心跳广播的 room 摘要)
      │     └─ 点房间条目 → [加入房间] → 连接房主 → 成功进入 / 失败提示
      └─ 点击进入 → RoomScreen(聊天室会话页)
            ├─ AppBar: 房间名 + 成员数 + [成员入口] + [离开/解散]
            ├─ 成员横条 RoomMemberBar: 头像+名字,点击可发起私聊
            ├─ 消息列表: 复用 MessageBubble(他人左/自己右/系统居中)
            └─ 输入栏: 文本发送(与 ChatScreen 输入栏一致,文件按钮 v1 隐藏)
```

### 5.2 创建房间流程(房主视角)

1. 聊天室 Tab 点击「创建房间」→ 弹窗输入房间名(默认 `我的房间-<设备名>`,限 30 字)。
2. 本地生成 `roomId`(uuid)→ 启动 `RoomHost`(22088 起候选端口)。
3. 建房成功 → 本机即房主,心跳广播追加 `room` 摘要;界面进入 `RoomScreen`(房主模式)。
4. 房主模式权限:解散房间、踢人(v1 可选);成员进出自动生成系统消息
   「XX 加入了房间 / XX 离开了房间」。

### 5.3 加入房间流程(成员视角)

1. 「附近房间」列表展示心跳里带 `room` 摘要的设备条目(房间名 + 房主名 + 成员数)。
2. 点击条目 → 确认弹窗 → `RoomClient.connect(房主IP, 房主端口)`。
3. 连接成功后发送 `room_join` → 收到 `room_join_ack`(含全量成员列表)→ 进入 `RoomScreen`(成员模式)。
4. 失败分支:
   - 连接超时/拒绝 → 提示「无法连接房主,请确认房主在线」,停留在列表页;
   - `room_join_reject(full)` → 提示「房间人数已满」;
   - 房主在加入过程中解散 → 提示「房间已解散」。

### 5.4 聊天流程

1. 成员发送:输入文本 → 本地立即上屏(状态 sending,与单聊一致)→ 发送 `room_msg` 给房主。
2. 房主校验 `senderId ∈ members` → 原样转发给**其他所有成员**。
3. 各成员(含发送者)按 `msgId` 去重后上屏,消息归档到 `peer_id='room:<roomId>'`。
4. 房主离线 → 成员端 `RoomClient` 断开 → 提示「房主已离线,房间已解散」→
   清空本地房间状态,自动回到聊天室列表页(保留本地历史)。

### 5.5 离开/解散流程

- **成员离开**:点「离开房间」→ 发 `room_leave` → 房主广播 `room_members(left)` → 本地清理。
- **房主解散**:点「解散房间」→ 广播 `room_close` → 停止 RoomHost → 心跳清除 room 摘要 →
  各成员收到后提示并回到列表页。

### 5.6 状态机(成员侧 RoomProvider)

```
idle ──点击加入──▶ joining ──ack──▶ joined
  ▲                  │失败(reject/超时)│
  │                  ▼                ▼
  │                idle(提示原因)   joined ──房主离线/解散──▶ idle(提示+清理)
  │                                    │离开
  └────────────────────────────────────┘
```

### 5.7 与单聊的交互约定

- 房间内点成员头像 → 直接进入现有单聊 `ChatScreen`(用该成员 deviceId 作为 peerId),
  房间消息与会话列表互不干扰。
- 房间消息持久化复用 `chat_messages` 表(peer_id 带 `room:` 前缀),
  会话列表 Tab 会显示房间会话(名字用房间名,图标区分房间/单聊)。

---

## 6. 实施步骤

| 阶段 | 内容 | 验证方式 |
|---|---|---|
| P0 协议与模型 | `room.dart` / `room_chat_message.dart`;`RoomHost`/`RoomClient` 骨架(建连、`room_join/ack/reject`) | 两台设备日志联调 |
| P1 房间核心 | 成员管理(增删/断线检测)、`room_msg` 转发+去重、`room_members` 广播、`room_leave/close` | 三台设备文字互通、成员进出正确 |
| P2 发现与 UI | 心跳 room 摘要、首页第三 Tab、`RoomListScreen`、`RoomScreen`、`RoomProvider`、i18n 文案 | 手动走通创建/加入/聊天/离开全流程 |
| P3 稳定性加固 | 转发背压/让出事件循环、消息大小限制、人数上限、重连/房主离线处理、单聊回归 | 大房间压力测试 + 单聊功能回归清单 |
| P4 后续增强(可选) | 历史同步、聊天室内文件转发、房主迁移/踢人 | 视需求排期 |

预计 P0~P3 为一次完整交付,工作量集中在 P1(转发/成员管理)与 P2(UI)。

---

## 7. 明确不做的边界(v1)

- 不做历史消息同步(新成员只看到加入后的消息)。
- 不做聊天室内文件传输(文件继续走单聊;点成员头像发起)。
- 不做房主迁移(房主离线即解散,语义清晰)。
- 不做房间密码/邀请码(局域网信任模型,可后续加)。
- 不做多房间同时加入(一台设备同一时刻只在一个房间,简化状态机)。



