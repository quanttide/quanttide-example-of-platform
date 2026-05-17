"""测试入口模块。"""

from argparse import ArgumentParser
from unittest.mock import MagicMock, patch

from app.main import main


class TestArgParse:
    """验证命令行参数解析。"""

    def test_default_data_path(self) -> None:
        parser = ArgumentParser()
        parser.add_argument("--data", default="data.json")
        args = parser.parse_args([])
        assert args.data == "data.json"

    def test_custom_data_path(self) -> None:
        parser = ArgumentParser()
        parser.add_argument("--data", default="data.json")
        args = parser.parse_args(["--data", "custom.json"])
        assert args.data == "custom.json"

    def test_module_importable(self) -> None:
        """验证模块可导入、main 函数可调用。"""
        import app.main as m

        assert callable(m.main)


class TestMainRepl:
    """验证 REPL 内置命令。"""

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_quit_via_eof(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """Ctrl+D (EOF) 退出。"""
        with patch("builtins.input", side_effect=EOFError):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                mock_print.assert_any_call("\n再见。")

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_quit_command(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """输入 /quit 退出。"""
        with patch("builtins.input", side_effect=["/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                mock_print.assert_any_call("再见。")

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_exit_command(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """输入 /exit 退出。"""
        with patch("builtins.input", side_effect=["/exit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                mock_print.assert_any_call("再见。")

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_unknown_command(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """未知命令提示。"""
        with patch("builtins.input", side_effect=["/unknown", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                mock_print.assert_any_call("未知命令: /unknown")

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_help_command(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """/help 显示帮助。"""
        with patch("builtins.input", side_effect=["/help", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                all_output = [str(c[0][0]) for c in mock_print.call_args_list]
                assert any("/quit" in line for line in all_output)
                assert any("/help" in line for line in all_output)

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_empty_input_skipped(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """空输入跳过，不报错。"""
        with patch("builtins.input", side_effect=["", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                mock_print.assert_any_call("再见。")

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_messages_command(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """/messages 显示消息列表。"""
        mock_store_instance = mock_store.return_value
        from app.models import Message, Role

        mock_store_instance.list_messages.return_value = [
            Message(content="hello", role=Role.user)
        ]
        with patch("builtins.input", side_effect=["/messages", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                all_output = " ".join(
                    str(c[0][0]) for c in mock_print.call_args_list if c[0]
                )
                assert "hello" in all_output

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_consensuses_command(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """/consensuses 显示共识列表。"""
        from app.models import Consensus

        mock_store_instance = mock_store.return_value
        mock_store_instance.list_consensuses.return_value = [
            Consensus(content="PostgreSQL")
        ]
        mock_store_instance.get_relations_for_consensus.return_value = []
        with patch("builtins.input", side_effect=["/consensuses", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                all_output = " ".join(
                    str(c[0][0]) for c in mock_print.call_args_list if c[0]
                )
                assert "PostgreSQL" in all_output

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_confirm_command(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """/confirm 成功则显示确认信息。"""
        from app.models import Consensus

        mock_storage_instance = mock_store.return_value
        mock_storage_instance.update_consensus_status.return_value = (
            Consensus.model_validate(
                {"id": "abc123", "content": "test", "status": "confirmed"}
            )
        )
        with patch("builtins.input", side_effect=["/confirm abc123", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                all_output = " ".join(
                    str(c[0][0]) for c in mock_print.call_args_list if c[0]
                )
                assert "已确认" in all_output

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_confirm_not_found(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """/confirm 找不到共识提示。"""
        mock_storage_instance = mock_store.return_value
        mock_storage_instance.update_consensus_status.return_value = None
        with patch("builtins.input", side_effect=["/confirm xxx", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                mock_print.assert_any_call("未找到该共识")

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_history_command(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """/history 显示历史（先发一条消息再查看）。"""
        mock_msg_instance = mock_msg.return_value
        mock_msg_instance.reply.return_value = "回复内容"
        with patch("builtins.input", side_effect=["你好", "/history", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                all_output = " ".join(str(c[0][0]) for c in mock_print.call_args_list if c[0])
                assert "你好" in all_output
                assert "回复内容" in all_output

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_deprecate_command(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """/deprecate 成功则显示确认信息。"""
        from app.models import Consensus

        mock_storage_instance = mock_store.return_value
        mock_storage_instance.update_consensus_status.return_value = (
            Consensus.model_validate(
                {"id": "abc123", "content": "test", "status": "deprecated"}
            )
        )
        with patch("builtins.input", side_effect=["/deprecate abc123", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                all_output = " ".join(
                    str(c[0][0]) for c in mock_print.call_args_list if c[0]
                )
                assert "已废弃" in all_output

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_deprecate_not_found(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """/deprecate 找不到共识提示。"""
        mock_storage_instance = mock_store.return_value
        mock_storage_instance.update_consensus_status.return_value = None
        with patch("builtins.input", side_effect=["/deprecate xxx", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                mock_print.assert_any_call("未找到该共识")

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_normal_conversation(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """正常对话流程：消息 → agent 回复 → consensus 观察。"""
        mock_msg_instance = mock_msg.return_value
        mock_con_instance = mock_con.return_value
        mock_store_instance = mock_store.return_value
        mock_store_instance.list_consensuses.return_value = []
        mock_msg_instance.reply.return_value = "你好，有什么可以帮助你的？"
        with patch("builtins.input", side_effect=["你好", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                mock_msg_instance.reply.assert_called_once()
                mock_con_instance.observe.assert_called_once()

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_messages_with_content(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """/messages 显示消息内容。"""
        mock_store_instance = mock_store.return_value
        from app.models import Message, Role

        mock_store_instance.list_messages.return_value = [
            Message(content="测试消息内容", role=Role.user)
        ]
        with patch("builtins.input", side_effect=["/messages", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                all_output = " ".join(
                    str(c[0][0]) for c in mock_print.call_args_list if c[0]
                )
                assert "测试消息内容" in all_output

    @patch("app.main.Storage")
    @patch("app.main.MessageAgent")
    @patch("app.main.ConsensusAgent")
    def test_consensuses_with_relations(
        self, mock_con: MagicMock, mock_msg: MagicMock, mock_store: MagicMock
    ) -> None:
        """/consensuses 显示有关联的共识。"""
        from app.models import Consensus, Relation

        mock_store_instance = mock_store.return_value
        mock_store_instance.list_consensuses.return_value = [
            Consensus(content="PostgreSQL")
        ]
        mock_store_instance.get_relations_for_consensus.return_value = [
            Relation(message_id="msg-1", consensus_id="c1")
        ]
        with patch("builtins.input", side_effect=["/consensuses", "/quit"]):
            with patch("builtins.print") as mock_print:
                main(argv=[])
                all_output = " ".join(
                    str(c[0][0]) for c in mock_print.call_args_list if c[0]
                )
                assert "msg-1" in all_output
