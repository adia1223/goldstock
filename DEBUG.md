# 本地调试指南

## 方式一：直接运行已编译的应用（最快）

如果已经有编译好的 `GoldStock.app`，可以直接运行：

```bash
cd <项目根目录>
open GoldStock.app
```

或者使用命令行：

```bash
./GoldStock.app/Contents/MacOS/GoldStock
```

## 方式二：使用 build.sh 重新编译并运行

```bash
cd <项目根目录>
chmod +x build.sh
./build.sh
open GoldStock.app
```

## 方式三：使用 swiftc 直接编译运行（适合调试）

```bash
cd <项目根目录>
swiftc -o GoldStock Sources/main.swift -framework Cocoa
./GoldStock
```

## 方式四：使用 Xcode 调试（推荐用于开发调试）

1. 在 Xcode 中打开项目：
   ```bash
   open -a Xcode <项目根目录>
   ```

2. 或者创建 Xcode 项目：
   ```bash
   swift package generate-xcodeproj
   open GoldStock.xcodeproj
   ```

3. 在 Xcode 中：
   - 选择 Scheme: `GoldStock`
   - 按 `Cmd + R` 运行
   - 按 `Cmd + .` 停止
   - 设置断点进行调试

## 调试技巧

### 查看日志输出

应用运行时，可以在终端查看日志：

```bash
# 如果直接运行二进制文件
./GoldStock.app/Contents/MacOS/GoldStock

# 或者使用 Console.app 查看系统日志
open -a Console
```

### 修改代码后重新编译

```bash
# 快速编译
swiftc -o GoldStock Sources/main.swift -framework Cocoa

# 或者使用 build.sh（会创建完整的 .app 包）
./build.sh
```

### 调试网络请求

代码中的网络请求在以下位置：
- 黄金价格：`GoldPriceService` 类
- 基金数据：`FundService` 类

可以在这些方法中添加 `print()` 语句来查看请求和响应。

### 常见问题

1. **权限问题**：如果遇到权限错误，可能需要：
   ```bash
   xattr -cr GoldStock.app
   ```

2. **首次运行**：macOS 可能会阻止未签名的应用，需要：
   - 右键点击应用 → 选择「打开」
   - 或在终端执行：`xattr -cr GoldStock.app`

3. **查看应用状态**：应用是菜单栏应用，启动后会在菜单栏显示图标。

## 快速调试命令

```bash
# 编译并运行（在项目根目录下执行）
swiftc -o GoldStock Sources/main.swift -framework Cocoa && ./GoldStock

# 或者使用 build.sh
./build.sh && open GoldStock.app
```
