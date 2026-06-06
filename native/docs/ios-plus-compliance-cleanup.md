# iOS Plus 授权合规清理清单

## 目标

让 EasyNode Mobile 在 iOS 上架时保持清晰定位：

> App 不销售数字内容，只访问用户自托管 EasyNode 服务端上的既有 Plus 能力。Plus 授权由用户连接的服务端管理，Mobile 端只展示服务端返回的授权状态，不主动提供购买、获取 key 或外部购买引导。

## 背景

当前 Plus 功能授权在服务端完成：

- Mobile 登录用户自己的 EasyNode 服务端。
- Mobile 调用服务端 `/plus-info` 查看 Plus 运行时状态。
- Mobile 调用服务端 `/plus-conf` 提交 Plus Key。
- EasyNode 服务端再向授权服务器激活 key，并在内存中保存解密 key。

因此，iOS App 不应表现为「在 App 内销售或引导购买 Plus」。否则容易被 Apple 认为是在绕过 IAP。

## 合规原则

### iOS 端原则

1. 不展示购买入口。
2. 不展示外部购买链接。
3. 不展示价格、折扣、优惠、购买提示。
4. 不使用「获取 Plus Key」「购买 Plus」「升级 Plus」等引导性文案。
5. 只展示当前连接服务端返回的 Plus 授权状态。
6. Plus 错误提示优先使用服务端下发内容。
7. 未授权时使用中性说明：Plus 由服务端管理，请在服务端完成授权后刷新。

### 非 iOS 端原则

Android / Web 是否保留购买入口可单独决定。为了最大程度降低审核风险，本清单只要求 iOS 隐藏购买引导。

## 需要修改的 mobile 文件

### 1. `lib/features/settings/plus_subscription_page.dart`

#### 当前风险点

当前文件存在固定外部购买链接：

```dart
const String _plusPurchaseUrl = 'https://en.221022.xyz/buy-plus';
```

当前 AppBar 右上角展示「获取 Plus Key」按钮：

```dart
child: _FetchKeyButton(onTap: _openPurchaseUrl),
```

当前折扣 banner 可点击外部购买链接：

```dart
onDiscountTap: _openPurchaseUrl,
```

这些在 iOS 上属于高风险购买引导。

#### 清理要求

- [ ] 引入平台判断，例如 `dart:io` 的 `Platform.isIOS`，或用 Flutter 平台能力判断当前是否 iOS。
- [ ] iOS 下隐藏 AppBar 右上角「获取 Plus Key」按钮。
- [ ] iOS 下不调用 `_openPurchaseUrl()`。
- [ ] iOS 下隐藏折扣 banner，或者只展示不可点击的服务端公告；推荐直接隐藏。
- [ ] iOS 下 `_ActivateCard` 不传入购买/折扣点击回调。
- [ ] iOS 下 `discount.discount` 即使为 true，也不展示跳转购买 UI。
- [ ] 保留 Plus Key 输入和激活能力，前提是文案不引导用户去购买。
- [ ] 保留 `/plus-info` 状态展示与刷新能力。

#### 建议实现形态

在页面内部计算：

```dart
final isIOS = Platform.isIOS;
```

AppBar actions：

```dart
actions: isIOS
    ? const []
    : [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _FetchKeyButton(onTap: _openPurchaseUrl),
        ),
      ],
```

激活卡片：

```dart
_ActivateCard(
  controller: _keyController,
  formKey: _formKey,
  discount: isIOS ? const PlusDiscount(discount: false, content: '') : _discount,
  loading: _activating,
  onSubmit: _activate,
  onDiscountTap: isIOS ? null : _openPurchaseUrl,
)
```

如果 `onDiscountTap` 改成 nullable：

```dart
final VoidCallback? onDiscountTap;
```

折扣区域只在非 iOS 且回调存在时展示：

```dart
if (widget.onDiscountTap != null &&
    widget.discount.discount &&
    widget.discount.content.isNotEmpty) ...[
  // discount banner
]
```

### 2. `lib/l10n/strings_zh.dart`

#### 当前风险点

当前文案：

```dart
'plus.fetchKey': '获取 Plus Key',
'plus.fetchKeyHint': '已复制购买地址到剪贴板：{0}',
'plus.activateHint': '如果你觉得好用，欢迎加入支持作者，让项目走得更远 ❤️',
'plus.discountTip': '限时优惠',
'plus.featuresTitle': 'Plus 专属功能',
```

其中 `获取 Plus Key`、`购买地址`、`限时优惠`、`支持作者` 都容易被审核理解为购买引导。

#### 清理要求

- [ ] iOS 可见页面不展示 `plus.fetchKey`。
- [ ] iOS 不触发 `plus.fetchKeyHint`。
- [ ] 将 `plus.activateHint` 改为中性文案。
- [ ] 如果 `plus.discountTip` 仅用于 iOS 隐藏区域，可以暂时保留；若 iOS 可见则必须移除。
- [ ] Plus 功能错误提示优先显示服务端返回内容，不在客户端写「请购买」「请升级」。

#### 建议中性中文文案

```dart
'plus.activateHint': 'Plus 授权由当前连接的 EasyNode 服务端管理。请在服务端完成授权后刷新状态。',
'plus.activateSuccess': '授权信息已提交，请刷新确认服务端状态',
'plus.activateFailed': '授权失败，请查看服务端返回信息',
```

如果需要新增状态说明：

```dart
'plus.iosManagedByServer': 'Plus 授权由当前连接的服务端管理，Mobile 端仅展示服务端返回的授权状态。',
```

### 3. `lib/l10n/strings_en.dart`

#### 当前风险点

当前文案：

```dart
'plus.fetchKey': 'Get Plus Key',
'plus.fetchKeyHint': 'Copied purchase URL to clipboard: {0}',
'plus.activateHint': 'If you find it helpful, consider supporting the author and keep the project going ❤️',
'plus.discountTip': 'Limited offer',
```

#### 清理要求

- [ ] iOS 可见页面不展示 `plus.fetchKey`。
- [ ] iOS 不触发 `plus.fetchKeyHint`。
- [ ] 将 `plus.activateHint` 改为中性文案。
- [ ] iOS 可见文案不得出现 purchase、buy、price、discount、offer、upgrade 等购买引导词。

#### 建议中性英文文案

```dart
'plus.activateHint': 'Plus authorization is managed by the connected EasyNode server. Complete authorization on the server, then refresh the status here.',
'plus.activateSuccess': 'Authorization info submitted. Refresh to confirm the server status.',
'plus.activateFailed': 'Authorization failed. Please check the server response.',
```

如需新增：

```dart
'plus.iosManagedByServer': 'Plus authorization is managed by the connected server. The mobile app only displays the server-reported authorization status.',
```

### 4. `lib/features/settings/models/plus_info.dart`

#### 当前状态

当前模型已有：

```dart
final String error;
```

并且说明为：

```dart
/// Human-readable error to surface when kicked / abnormal.
```

#### 清理要求

- [ ] 保留 `error` 字段。
- [ ] Plus 状态异常时优先展示服务端返回的 `error`。
- [ ] 客户端 fallback 文案保持中性，不写购买引导。

### 5. `lib/features/servers/server_form_page.dart`

#### 当前风险点

当前 iOS 可见 Plus gating 文案可能是：

```dart
'代理 / 跳板机为 Plus 专属功能'
```

这类文案本身问题不大，但不应搭配购买入口或购买链接。

#### 清理要求

- [ ] 未授权时只提示该能力由服务端 Plus 状态控制。
- [ ] 不出现「购买」「升级」「获取 Key」等引导。
- [ ] 如果能拿到服务端 Plus 错误信息，则展示服务端下发错误。

建议中文：

```dart
'该能力需要当前连接的服务端已启用 Plus。请在服务端完成授权后重试。'
```

建议英文：

```dart
'This capability requires Plus to be active on the connected server. Complete authorization on the server and try again.'
```

### 6. `lib/features/servers/servers_tab.dart`

#### 当前风险点

连接代理 / 跳板机时未授权会提示：

```dart
'代理类型错误，请激活 Plus 功能后重试'
```

#### 清理要求

- [ ] 替换为中性服务端授权文案。
- [ ] 不提示购买或获取 key。

建议中文：

```dart
'当前连接的服务端尚未启用 Plus，无法使用代理 / 跳板机。'
```

建议英文：

```dart
'Plus is not active on the connected server, so proxy / jump host cannot be used.'
```

### 7. `lib/features/scripts/script_groups_page.dart`

#### 当前状态

脚本分组受 `isPlusActiveProvider` 控制。

#### 清理要求

- [ ] 未授权提示保持中性。
- [ ] 不加入购买按钮。
- [ ] 不跳转 Plus 购买页。

建议中文：

```dart
'该能力需要当前连接的服务端已启用 Plus。'
```

建议英文：

```dart
'This capability requires Plus to be active on the connected server.'
```

## 服务端下发错误提示要求

### 当前服务端能力

`/plus-info` 当前返回：

```js
{
  key,
  instanceId,
  active,
  status,
  needRestart,
  tokenExpireAt,
  error
}
```

文件：`easynode/server/app/controller/user.js`

客户端模型已经接收 `error`。

### 清理要求

- [ ] Plus 页面状态展示优先使用 `/plus-info` 的 `error`。
- [ ] `/plus-conf` 激活失败时继续使用服务端返回的 `msg`。
- [ ] 客户端只保留中性 fallback。
- [ ] 服务端错误文案可以说明授权状态、占用、过期、失效，但不要在 iOS 客户端表现为购买引导。

## iOS App Review 备注建议

提交审核时，在 App Review Notes 中说明：

```text
EasyNode Mobile is a client app for connecting to a user self-hosted EasyNode server. Plus capabilities are authorized and managed on the connected server. The iOS app does not sell digital content or provide purchase links; it only displays the authorization status reported by the user's server.
```

中文含义：

```text
EasyNode Mobile 是连接用户自托管 EasyNode 服务端的客户端。Plus 能力在用户连接的服务端上授权和管理。iOS App 不销售数字内容，也不提供购买链接，只展示用户服务端返回的授权状态。
```

## 验收清单

### 代码搜索验收

在 iOS 构建相关可见代码中，应确认：

- [ ] 没有可触发的外部购买 URL。
- [ ] 没有 iOS 可见的「获取 Plus Key」按钮。
- [ ] 没有 iOS 可见的折扣、优惠、限时活动入口。
- [ ] 没有 iOS 可见的 purchase / buy / discount / offer / upgrade 购买引导文案。
- [ ] Plus 未授权时没有跳转购买页面。
- [ ] Plus 未授权时只展示服务端授权状态或中性提示。

### 手动验收

在 iOS 模拟器或真机中检查：

- [ ] 打开 Plus 页面，不显示「获取 Plus Key」按钮。
- [ ] 打开 Plus 页面，不显示购买链接。
- [ ] 服务端返回折扣公告时，iOS 不显示可点击购买 banner。
- [ ] 输入已有 Plus Key 仍可提交到当前连接的服务端。
- [ ] `/plus-info` 返回 active 时，Plus 状态正常展示。
- [ ] `/plus-info` 返回 kicked / inactive / unset 时，提示文案中性。
- [ ] 使用代理 / 跳板机 / 脚本分组等 Plus 功能时，未授权提示不引导购买。

## 推荐实施顺序

1. 修改 `plus_subscription_page.dart`，加 iOS 平台判断，隐藏购买入口和折扣 banner。
2. 修改 `strings_zh.dart` / `strings_en.dart` 的 Plus 文案为中性描述。
3. 检查 Plus gating 文案：服务器代理、跳板机、脚本分组。
4. 确认 Plus 错误优先用服务端下发内容。
5. 在 iOS 模拟器跑一遍 Plus 页面和受限功能。
6. 搜索购买相关关键词，确认 iOS 可见路径无购买引导。

## 不在本次清理范围内

以下内容不建议本次一起做：

- Apple IAP。
- RevenueCat。
- App Store Server Notifications。
- 终端用户账号系统。
- 网站购买和 IAP 的统一权益系统。
- License 表增加 Apple 交易字段。

这些属于后续「C 方案」的大改造，不是本次 iOS 上架合规清理的目标。
