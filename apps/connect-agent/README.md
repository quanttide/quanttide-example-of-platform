# connect-agent

人机沟通共识引擎。基于双智能体架构（消息智能体 System 1 + 共识智能体 System 2），从对话中自动提炼并维护共识卡片。

参见 [docs/connect-agent/](../docs/connect-agent/) 获取完整设计文档。

## 运行

```bash
uv run python -m app.main
```

## 测试

| 类别 | 命令 | 说明 |
|------|------|------|
| 单元测试 | `uv run pytest tests/` | 77 个，99% 覆盖率，无外部依赖 |
| 集成测试 | `uv run pytest integration_tests/` | 4 个，需 Vault + DeepSeek API |
| 覆盖率 | `uv run pytest --cov=app tests/` | |
