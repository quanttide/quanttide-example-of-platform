"""
connect-agent 配置

从 Vault 读取 DeepSeek API key。
"""

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, PydanticBaseSettingsSource
from pydantic_vault import VaultSettingsSource


class Settings(BaseSettings):
    """应用配置，优先从环境变量读取，其次从 Vault 读取。"""

    llm_api_key: SecretStr = Field(
        ...,
        description="DeepSeek API key",
        json_schema_extra={
            "vault_secret_path": "quanttide/deepseek",
            "vault_secret_key": "api_key",
        },
    )

    model_config = {}

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        return (
            init_settings,
            env_settings,
            dotenv_settings,
            VaultSettingsSource(settings_cls),
            file_secret_settings,
        )


settings = Settings()
