param(
    [string]$platform = ""
)

# `.patch` 统一按 UTF-8 读、按 UTF-8 写（不带 BOM）。
#
# 别改用 `Get-Content` / `Set-Content`：Windows PowerShell 5.1 不带 `-Encoding`
# 时走**系统 ANSI 代码页**（中文 Windows 上是 GBK），补丁里的中文注释会被这一步
# 写成乱码，字节一变行也跟着少，`git apply` 就报 "corrupt patch at line N"
# （`lib/scripts/material/tabs.patch` 里那几行 `// PiliPlus: 手柄/遥控器…` 的注释
# 就是这么被吃掉 7 行的）。顺手把 CRLF 统一成 LF：`git apply` 不认 CRLF 的补丁。
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
function Convert-PatchToLf([string]$path) {
    $text = [System.IO.File]::ReadAllText($path, $utf8NoBom)
    $lf = $text -replace "`r`n", "`n"
    # 已经是 LF 就一个字节都别动
    if ($lf -ne $text) {
        [System.IO.File]::WriteAllText($path, $lf, $utf8NoBom)
    }
}

# 取本项目**实际依赖**的那一份包目录（pub 缓存里的绝对路径）。
#
# 不能按版本号猜（`Get-ChildItem ... | Select-Object -Last 1` 只按名字排）：
# pub 缓存是**跨项目共享**的，同一个包通常躺着好几个版本，别的项目 `pub get`
# 装进来的新版本会在名字上"更大"，于是脚本跑去补丁一个本项目根本不用的版本，
# 甚至把它整目录删掉——而 `flutter pub get` 不会重新下载它（不在本项目的
# pubspec.lock 里），第二轮只好转头去动真正在用的那一份（见下方 material_ui 段）。
# `.dart_tool/package_config.json` 是 pub 自己写的解析结果，只有它说了算。
function Resolve-CachedPackageDir([string]$name) {
    $config = "$env:GITHUB_WORKSPACE/.dart_tool/package_config.json"
    if (Test-Path $config) {
        try {
            $packages = (Get-Content $config -Raw -Encoding UTF8 | ConvertFrom-Json).packages
            $package = $packages | Where-Object { $_.name -eq $name } | Select-Object -First 1
            if ($package -and $package.rootUri) {
                $path = ([System.Uri]$package.rootUri).LocalPath.TrimEnd('\', '/')
                if (Test-Path $path) { return Get-Item $path }
            }
        } catch {
            # package_config.json 读不动就退回去按名字取最新的那个（下面的兜底）
        }
    }
    return Get-ChildItem "$PubCacheDir/hosted/pub.dev" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$name-*" } | Select-Object -Last 1
}

# TODO: remove
# https://github.com/flutter/flutter/issues/182281
$NewOverScrollIndicator = "362b1de29974ffc1ed6faa826e1df870d7bec75f";

# set `gestureSettings`
$BottomSheetAndroidPatch = "lib/scripts/bottom_sheet_android.patch"

# https://github.com/bggRGjQaUbCoE/PiliPlus/issues/1906
$BottomSheetIOSFlutterPatch = "lib/scripts/bottom_sheet_ios_flutter.patch"
$BottomSheetIOSPiliPlusPatch = "lib/scripts/bottom_sheet_ios_piliplus.patch"

# https://github.com/bggRGjQaUbCoE/PiliPlus/issues/1662
# handle bottom scroll event
$ScrollViewPatch = "lib/scripts/scroll_view.patch"

# https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2106
# use `TouchGestureRecognizer` on all platforms
$TextSelectionPatch = "lib/scripts/text_selection.patch"

# https://github.com/bggRGjQaUbCoE/PiliPlus/issues/1947
$NavigatorPatch = "lib/scripts/navigator.patch"

# https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2107
$ImageAnimPatch = "lib/scripts/image_anim.patch"

# remove `_scheduleRebuild`
$LayoutBuilderPatch = "lib/scripts/layout_builder.patch"

# https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2308
$NavigationDrawerPatch = "lib/scripts/navigation_drawer.patch"

# apply text color to icon color
$PopupMenuPatch = "lib/scripts/popup_menu.patch"

# remove `Hero` effect
$FABPatch = "lib/scripts/fab.patch"

# https://github.com/flutter/flutter/issues/139890
# https://github.com/flutter/flutter/issues/174689
# separator support
# clamp handle offset
# widgetspan selection support
# clear selection when tapping outside
# free selection if there is only one text
# clamp dragging selection behavior on Android
# show selection menu if secondary tap position is in text region on desktop
$SelectableRegionPatch = "lib/scripts/selectable_region.patch"

# https://github.com/flutter/flutter/issues/132047
# https://github.com/flutter/flutter/issues/174689
$EditableTextPatch = "lib/scripts/editable_text.patch"

# set `selectAllOnFocus` to `false` by default
$TextFieldPatch = "lib/scripts/text_field.patch"

# notify `userScrollDirection` only if position is actually changing
$ScrollPositionPatch = "lib/scripts/scroll_position.patch"

# expose `_shouldIgnorePointer`
$ScrollablePatch = "lib/scripts/scrollable.patch"

# expose
$ScaffoldPatch = "lib/scripts/scaffold.patch"

# fix nested scrollable gesture
# custom `HorizontalDragGestureRecognizer` support
$ScrollableGesturePatch = "lib/scripts/scrollable_gesture.patch"

# expose
$DraggableScrollableSheetPatch = "lib/scripts/draggable_scrollable_sheet.patch"

# expose
$TextPatch = "lib/scripts/text.patch"

# expose
$TextPainterPatch = "lib/scripts/text_painter.patch"

$SliverPatch = "lib/scripts/sliver.patch"

$RefreshIndicatorPatch = "lib/scripts/refresh_indicator.patch"

# TODO: remove
# https://github.com/flutter/flutter/issues/124078
# https://github.com/flutter/flutter/pull/183261
$NullSafetySelectableRegionPatch = "lib/scripts/null_safety_for_selectable_region.patch"

# TODO: remove
# https://github.com/flutter/flutter/issues/90223
$ModalBarrierPatch = "lib/scripts/modal_barrier.patch"

# TODO: remove
# https://github.com/flutter/flutter/issues/182466
$MouseCursorPatch = "lib/scripts/mouse_cursor.patch"

$GeetestIOSPatch = "lib/scripts/geetest_ios.patch"

if ($platform.ToLower() -eq "ios") {
    git apply $BottomSheetIOSPiliPlusPatch
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$BottomSheetIOSPiliPlusPatch applied"
    } else {
        throw "$LASTEXITCODE"
    }
    git apply $GeetestIOSPatch
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$GeetestIOSPatch applied"
    } else {
        throw "$LASTEXITCODE"
    }
}

# 防止在 FLUTTER_ROOT 缺失时于错误目录执行 git reset 等破坏性命令
if (-not $env:FLUTTER_ROOT -or -not (Test-Path "$env:FLUTTER_ROOT/bin/flutter")) {
    throw "FLUTTER_ROOT 未设置或无效，请通过 build_android.bat / build_windows.bat 运行本脚本"
}

Set-Location $env:FLUTTER_ROOT

$picks   = @()
$reverts = @()
$patches = @($ModalBarrierPatch, $TextSelectionPatch, $MouseCursorPatch,
            $ImageAnimPatch, $LayoutBuilderPatch, $NavigationDrawerPatch,
            $PopupMenuPatch, $FABPatch, $NullSafetySelectableRegionPatch,
            $SelectableRegionPatch, $EditableTextPatch, $TextFieldPatch,
            $ScrollPositionPatch, $ScrollablePatch, $ScrollableGesturePatch,
            $DraggableScrollableSheetPatch, $ScaffoldPatch, $TextPatch,
            $TextPainterPatch, $SliverPatch, $RefreshIndicatorPatch)

switch ($platform.ToLower()) {
    "android" {
        $patches += $BottomSheetAndroidPatch
        $patches += $ScrollViewPatch
        $patches += $NavigatorPatch
    }
    "ios" {
        $patches += $ScrollViewPatch
        $patches += $BottomSheetIOSFlutterPatch
        $patches += $NavigatorPatch
    }
    "linux" {
    }
    "macos" {
    }
    "windows" {
    }
    default {}
}

# ---------- 安全策略: 不执行 git reset --hard，绝不静默丢弃 Flutter SDK 的未提交修改 ----------
# 若 SDK 工作区有修改，仅当修改恰好等于"补丁已全部应用"（上次构建残留）时继续，
# 否则报错中止，由用户手动决定如何处理。
$sdkDirty = git status --porcelain 2>$null
if ($LASTEXITCODE -eq 0 -and $sdkDirty) {
    $allPatchesApplied = $true
    foreach ($patch in $patches) {
        git apply -R --check "$env:GITHUB_WORKSPACE/$patch" 2>$null
        if ($LASTEXITCODE -ne 0) {
            $allPatchesApplied = $false
            break
        }
    }
    if (-not $allPatchesApplied) {
        throw "Flutter SDK 工作区存在未提交修改且与补丁状态不符，已中止（不会自动丢弃这些修改）。请先检查: git -C '$env:FLUTTER_ROOT' status，确认无重要内容后手动还原 SDK（如 git -C '$env:FLUTTER_ROOT' checkout .）再重试"
    }
}

if ($picks.Count -gt 0 -or $reverts.Count -gt 0) {
    # 仅写入 SDK 仓库本地配置，避免污染用户全局 git 身份
    git config user.name "ci"
    git config user.email "example@example.com"
}

foreach ($pick in $picks) {
    git stash
    git cherry-pick $pick --no-edit
    if ($LASTEXITCODE -eq 0) {
        git reset --soft HEAD~1
        Write-Host "$pick picked"
    } else {
        throw "$LASTEXITCODE"
    }
    git stash pop
}

foreach ($revert in $reverts) {
    git stash
    git revert $revert --no-edit
    if ($LASTEXITCODE -eq 0) {
        git reset --soft HEAD~1
        Write-Host "$revert reverted"
    } else {
        throw "$LASTEXITCODE"
    }
    git stash pop
}

foreach ($patch in $patches) {
    git apply -R --check "$env:GITHUB_WORKSPACE/$patch" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$patch already applied"
        continue
    }
    git apply "$env:GITHUB_WORKSPACE/$patch"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$patch applied"
    } else {
        throw "$LASTEXITCODE"
    }
}

Set-Location $env:GITHUB_WORKSPACE

$BottomSheetAndroidPatchMaterial = "lib/scripts/material/bottom_sheet_android.patch"

$BottomSheetIOSFlutterMaterialPatchMaterial = "lib/scripts/material/bottom_sheet_ios_flutter_material.patch"

$ModalBarrierPatchMaterial = "lib/scripts/material/modal_barrier_material.patch"

$NavigationDrawerPatchMaterial = "lib/scripts/material/navigation_drawer.patch"

$PopupMenuPatchMaterial = "lib/scripts/material/popup_menu.patch"

$FABPatchMaterial = "lib/scripts/material/fab.patch"

$TextFieldPatchMaterial = "lib/scripts/material/text_field.patch"

$ScaffoldPatchMaterial = "lib/scripts/material/scaffold.patch"

$RefreshIndicatorPatchMaterial = "lib/scripts/material/refresh_indicator.patch"

$TabsPatchMaterial = "lib/scripts/material/tabs.patch"

$patches_material = @($ModalBarrierPatchMaterial, $NavigationDrawerPatchMaterial, $PopupMenuPatchMaterial,
                    $FABPatchMaterial, $TextFieldPatchMaterial, $ScaffoldPatchMaterial, $RefreshIndicatorPatchMaterial,
                    $TabsPatchMaterial)

$PubCacheDir = "~/.pub-cache"

switch ($platform.ToLower()) {
    "android" {
        $patches_material += $BottomSheetAndroidPatchMaterial
        # Windows 本地构建时 pub 缓存位于 %LOCALAPPDATA%\Pub\Cache，而非 ~/.pub-cache
        if ($env:OS -eq 'Windows_NT') {
            $PubCacheDir = "$env:LOCALAPPDATA/Pub/Cache"
        }
    }
    "ios" {
        $patches_material += $BottomSheetIOSFlutterMaterialPatchMaterial
    }
    "linux" {
    }
    "macos" {
    }
    "windows" {
        $PubCacheDir = "$env:LOCALAPPDATA/Pub/Cache"
    }
    default {}
}

$MaterialUiDir = Resolve-CachedPackageDir "material_ui"

# material_ui 在 pub 缓存内就地打补丁。
#
# 逐条判断、只补缺的那几条：已经打上的（`-R --check` 能过）直接跳过，
# 和上面 Flutter SDK 那一段（$patches 循环）同一个写法。
#
# 别写成"要么全打过、要么整包重下再全部重打"：只要有一条对不上（有人在缓存里
# 手工改过、或取包目录时挑错了版本——见上面 Resolve-CachedPackageDir 的注释），
# 就会走整包重下 + 全部重打；而重下这条路并不总是成立（重下的可能是别的版本，
# 也可能压根重下不了），第二轮仍然对着已经打好补丁的文件"全部重打"，
# 列表第一条（modal_barrier，补丁内容是 `lib/src/popup_menu.dart:1023`）当场
# `patch does not apply` 把构建打断——报错看着像补丁本身坏了，其实是把打好的
# 补丁又打了一遍。
#
# 就地打补丁而不是每次重下：重下会失效 Flutter 增量编译缓存，导致偶发
# "Type not found" 类构建失败。
$materialMissing = @()
if ($MaterialUiDir) {
    Push-Location $MaterialUiDir.FullName
    foreach ($patch in $patches_material) {
        git apply -R --check "$env:GITHUB_WORKSPACE/$patch" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$patch already applied"
            continue
        }
        $materialMissing += $patch
    }
    Pop-Location
} else {
    $materialMissing = @($patches_material)
}

if ($materialMissing.Count -gt 0) {
    Get-ChildItem -Path "$env:GITHUB_WORKSPACE/lib/scripts/material" -Filter *.patch | ForEach-Object {
        Convert-PatchToLf $_.FullName
    }

    if (-not $MaterialUiDir) {
        flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw "flutter pub get 失败，请检查网络与 Flutter SDK 版本: $LASTEXITCODE"
        }
        $MaterialUiDir = Resolve-CachedPackageDir "material_ui"
        if (-not $MaterialUiDir) {
            throw "material_ui package not found in pub cache"
        }
    }

    # 缺的补丁里，有连"打得动"都不成立的，说明包体和补丁已经对不上
    # （版本被换过、或有人在缓存里手工改过）——只有这一种才值得重下 pristine 包体。
    Push-Location $MaterialUiDir.FullName
    $materialDrifted = @()
    foreach ($patch in $materialMissing) {
        git apply --check "$env:GITHUB_WORKSPACE/$patch" 2>$null
        if ($LASTEXITCODE -ne 0) {
            $materialDrifted += $patch
        }
    }
    Pop-Location

    if ($materialDrifted.Count -gt 0) {
        Write-Host "material_ui 包体与补丁不符（$($materialDrifted -join ', ')），重新下载包体"
        try {
            Remove-Item -Path $MaterialUiDir.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            throw "无法删除 pub 缓存中的 material_ui（可能被其他进程占用）: $($MaterialUiDir.FullName)"
        }
        if (Test-Path $MaterialUiDir.FullName) {
            throw "material_ui 目录删除后仍然存在，请手动删除后重试: $($MaterialUiDir.FullName)"
        }

        flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw "flutter pub get 失败，请检查网络与 Flutter SDK 版本: $LASTEXITCODE"
        }

        $MaterialUiDir = Resolve-CachedPackageDir "material_ui"
        if (-not $MaterialUiDir) {
            throw "material_ui package not found in pub cache"
        }
    }

    Push-Location $MaterialUiDir.FullName
    foreach ($patch in $materialMissing) {
        git apply "$env:GITHUB_WORKSPACE/$patch"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$patch applied"
        } else {
            throw "${patch}: git apply 失败（退出码 $LASTEXITCODE），$($MaterialUiDir.Name) 已被打成半成品，删除该目录后重试"
        }
    }
    Pop-Location
} else {
    Write-Host "material_ui patches already applied"
}

$BottomSheetIOSFlutterPatchCupertino = "lib/scripts/cupertino/bottom_sheet_ios_flutter.patch"

$patches_cupertino = @()

switch ($platform.ToLower()) {
    "android" {
    }
    "ios" {
        $patches_cupertino += $BottomSheetIOSFlutterPatchCupertino
    }
    "linux" {
    }
    "macos" {
    }
    "windows" {
    }
    default {}
}

# 同一件事：取本项目实际依赖的那一份，别按名字取最大的
# （缓存里 cupertino_ui 同时有 1.0.2 和 1.1.1，而本项目在用的是 1.0.2）。
$CupertinoUiDir = Resolve-CachedPackageDir "cupertino_ui"

if (-not $CupertinoUiDir) {
    throw "cupertino_ui package not found in pub cache"
}

Write-Host "cupertino_ui dir: $($CupertinoUiDir.FullName)"

Get-ChildItem -Path "$env:GITHUB_WORKSPACE/lib/scripts/cupertino" -Filter *.patch | ForEach-Object {
    Convert-PatchToLf $_.FullName
}

Push-Location $CupertinoUiDir.FullName

foreach ($patch in $patches_cupertino) {
    git apply -R --check "$env:GITHUB_WORKSPACE/$patch" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$patch already applied"
        continue
    }
    git apply "$env:GITHUB_WORKSPACE/$patch"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$patch applied"
    } else {
        throw "${patch}: git apply 失败（退出码 $LASTEXITCODE）"
    }
}

Pop-Location
