#!/bin/bash
# 用 Xcode 工程打包成 macOS .app Bundle
# 用法：./build-app.sh   (在 EPLViewer/ 目录下)
# 结果：./build/EPLViewer.app   (双击或 open 启动，无 Terminal 窗口)
#
# 前置：EPLViewer.xcodeproj（纯 Xcode 工程，无 Package.swift / project.yml / XcodeGen）

set -e

# 切到脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "${SCRIPT_DIR}"

APP_NAME="EPLViewer"
SCHEME="EPLViewer"
CONFIG="Release"
DERIVED_DIR="build/DerivedData"
APP_SRC="${DERIVED_DIR}/Build/Products/${CONFIG}/${APP_NAME}.app"
APP_DST="build/${APP_NAME}.app"

echo "==> 1/2 编译 release (xcodebuild)"
xcodebuild -project EPLViewer.xcodeproj \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -derivedDataPath "${DERIVED_DIR}" \
  build

if [ ! -d "${APP_SRC}" ]; then
  echo "编译产物未找到：${APP_SRC}" >&2
  exit 1
fi

echo "==> 2/2 复制到 ${APP_DST}"
rm -rf "${APP_DST}"
cp -R "${APP_SRC}" "${APP_DST}"

echo ""
echo "✅ 完成：${APP_DST}"
echo "启动方式：open ${APP_DST}   或直接双击"
echo "脱离终端：从此不再有命令行窗口"
