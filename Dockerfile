# ============================================
# 红墨 AI 图文生成器 - Docker 镜像
# ============================================

# 阶段1: 构建前端
FROM node:22-slim AS frontend-builder

# 设置工作目录
WORKDIR /app/frontend

# 使用 corepack 管理 pnpm，缓存依赖加速重建
ENV PNPM_HOME=/root/.local/share/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable

# 启用 corepack 并安装 pnpm（使用指定版本避免兼容性问题）
RUN corepack enable && \
    corepack prepare pnpm@9.15.0 --activate && \
    pnpm config set registry https://registry.npmmirror.com && \
    pnpm --version

# 复制依赖配置文件，避免无关文件干扰缓存
COPY frontend/package.json frontend/pnpm-lock.yaml ./

# 安装前端依赖（增加重试和详细日志）
RUN pnpm install --frozen-lockfile --production=false --verbose

# 复制前端源码
COPY frontend/ ./

# 构建前端生产版本
RUN pnpm build


# 阶段2: 最终镜像
FROM python:3.12-slim

# 设置环境变量（运行时优化）
ENV TZ=Asia/Shanghai

# 设置工作目录
WORKDIR /app

# 安装运行时必需的系统依赖
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# 安装 uv (Python 包管理器)
RUN pip install --no-cache-dir uv

# 复制 Python 项目配置文件
COPY pyproject.toml uv.lock ./

# # 安装 Python 依赖
RUN uv sync --frozen --no-dev

# 复制后端代码
COPY backend/ ./backend/

# 复制空白配置文件模板（不包含任何 API Key）
COPY docker/text_providers.yaml ./
COPY docker/image_providers.yaml ./

# 复制前端构建产物
COPY --from=frontend-builder /app/frontend/dist ./frontend/dist

# 创建数据目录
RUN mkdir -p output history

# 设置环境变量
ENV FLASK_DEBUG=False \
    FLASK_HOST=0.0.0.0 \
    FLASK_PORT=12398

# 暴露端口
EXPOSE 12398

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:12398/api/health')" || exit 1

# 启动命令
CMD ["uv", "run", "python", "-m", "backend.app"]
