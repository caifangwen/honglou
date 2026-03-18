@echo off
REM 红楼回忆志 - 本地开发环境启动脚本

echo ========================================
echo 红楼回忆志 - 本地开发环境
echo ========================================
echo.

REM 1. 检查 Docker 是否运行
docker ps >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] Docker 未运行，请先启动 Docker Desktop
    pause
    exit /b 1
)

echo [1/3] 启动本地数据库环境...
docker-compose -f docker-compose.local-dev.yml --project-name honglou up -d

echo.
echo [2/3] 等待数据库初始化完成...
timeout /t 15 /nobreak >nul

echo.
echo [3/3] 重启 pgREST 以加载 schema 缓存...
docker-compose -f docker-compose.local-dev.yml --project-name honglou restart pgrest
timeout /t 5 /nobreak >nul

echo.
echo 验证服务状态...
docker ps --filter "name=honglou" --format "table {{.Names}}\t{{.Status}}"

echo.
echo ========================================
echo 服务已启动！
echo ========================================
echo - pgREST API: http://localhost:3000
echo - pgAdmin: http://localhost:5050
echo - PostgreSQL: localhost:5432
echo.
echo 测试账号：
echo - 袭人 (丫鬟): xiren@example.com / 123456
echo - 晴雯 (丫鬟): qingwen@example.com / 123456
echo - 凤姐 (管家): fengjie@example.com / 123456
echo.
echo 按任意键启动游戏...
pause >nul

REM 启动游戏（带本地模式参数）
godot --use-local-db=true
