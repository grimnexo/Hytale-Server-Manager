import sys
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

from PyQt6.QtCore import Qt, QObject, QRunnable, QThreadPool, QUrl, pyqtSignal
from PyQt6.QtGui import QDesktopServices, QFont
from PyQt6.QtWidgets import (
    QApplication,
    QDialog,
    QFormLayout,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QPlainTextEdit,
    QSpinBox,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)


@dataclass
class InstanceInfo:
    name: str
    path: Path
    container_name: str
    host_port: str
    image: str
    server_cmd: str


def parse_env_file(path: Path) -> Dict[str, str]:
    data: Dict[str, str] = {}
    if not path.exists():
        return data
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


def run_command(args: List[str], cwd: Optional[Path] = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        shell=False,
    )


def docker_available() -> bool:
    try:
        result = run_command(["docker", "version", "--format", "{{.Server.Version}}"])
        return result.returncode == 0
    except FileNotFoundError:
        return False


def docker_status(container_name: str) -> str:
    if not container_name:
        return "unknown"
    try:
        result = run_command(["docker", "inspect", "-f", "{{.State.Status}}", container_name])
    except FileNotFoundError:
        return "docker missing"
    if result.returncode != 0:
        return "not found"
    return result.stdout.strip() or "unknown"


class WorkerSignals(QObject):
    finished = pyqtSignal(int, str, str)


class CommandWorker(QRunnable):
    def __init__(self, args: List[str], cwd: Optional[Path] = None) -> None:
        super().__init__()
        self.args = args
        self.cwd = cwd
        self.signals = WorkerSignals()

    def run(self) -> None:
        try:
            result = run_command(self.args, self.cwd)
            self.signals.finished.emit(result.returncode, result.stdout, result.stderr)
        except FileNotFoundError as exc:
            self.signals.finished.emit(1, "", str(exc))


class CreateInstanceDialog(QDialog):
    def __init__(self, parent: QWidget) -> None:
        super().__init__(parent)
        self.setWindowTitle("Create Instance")
        self.setModal(True)

        self.base_name = QLineEdit("hytale")
        self.host_port = QSpinBox()
        self.host_port.setRange(1, 65535)
        self.host_port.setValue(25565)
        self.server_url = QLineEdit("")
        self.server_sha = QLineEdit("")
        self.server_cmd = QLineEdit("")

        form = QFormLayout()
        form.addRow("Base name", self.base_name)
        form.addRow("Host port", self.host_port)
        form.addRow("Server URL", self.server_url)
        form.addRow("Server SHA256", self.server_sha)
        form.addRow("Server command", self.server_cmd)

        self.create_btn = QPushButton("Create")
        self.cancel_btn = QPushButton("Cancel")
        self.create_btn.clicked.connect(self.accept)
        self.cancel_btn.clicked.connect(self.reject)

        btn_row = QHBoxLayout()
        btn_row.addStretch(1)
        btn_row.addWidget(self.cancel_btn)
        btn_row.addWidget(self.create_btn)

        layout = QVBoxLayout()
        layout.addLayout(form)
        layout.addLayout(btn_row)
        self.setLayout(layout)

    def build_instance_name(self) -> str:
        base = self.base_name.text().strip() or "hytale"
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        return f"{base}-{ts}"

    def instance_values(self) -> Dict[str, str]:
        return {
            "instance_name": self.build_instance_name(),
            "host_port": str(self.host_port.value()),
            "server_url": self.server_url.text().strip(),
            "server_sha256": self.server_sha.text().strip(),
            "server_cmd": self.server_cmd.text().strip(),
        }


class MainWindow(QMainWindow):
    def __init__(self, root_dir: Path) -> None:
        super().__init__()
        self.root_dir = root_dir
        self.instances_dir = self.root_dir / "instances"
        self.templates_dir = self.root_dir / "templates"
        self.thread_pool = QThreadPool.globalInstance()
        self.instances: List[InstanceInfo] = []

        self.setWindowTitle("Hytale Instance Manager")
        self.resize(980, 620)

        self.table = QTableWidget(0, 5)
        self.table.setHorizontalHeaderLabels([
            "Instance",
            "Container",
            "Status",
            "Port",
            "Image",
        ])
        self.table.verticalHeader().setVisible(False)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QTableWidget.SelectionMode.SingleSelection)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.itemSelectionChanged.connect(self.on_selection_changed)
        self.table.horizontalHeader().setStretchLastSection(True)

        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        self.log_view.setFont(QFont("Consolas", 9))

        self.refresh_btn = QPushButton("Refresh")
        self.start_btn = QPushButton("Start")
        self.stop_btn = QPushButton("Stop")
        self.restart_btn = QPushButton("Restart")
        self.logs_btn = QPushButton("Logs")
        self.open_btn = QPushButton("Open Folder")
        self.create_btn = QPushButton("Create Instance")

        self.refresh_btn.clicked.connect(self.refresh_instances)
        self.start_btn.clicked.connect(lambda: self.run_compose_action("up", "-d"))
        self.stop_btn.clicked.connect(lambda: self.run_compose_action("stop"))
        self.restart_btn.clicked.connect(lambda: self.run_compose_action("restart"))
        self.logs_btn.clicked.connect(self.fetch_logs)
        self.open_btn.clicked.connect(self.open_instance_folder)
        self.create_btn.clicked.connect(self.create_instance)

        action_box = QGroupBox("Actions")
        action_layout = QGridLayout()
        action_layout.addWidget(self.refresh_btn, 0, 0)
        action_layout.addWidget(self.start_btn, 0, 1)
        action_layout.addWidget(self.stop_btn, 0, 2)
        action_layout.addWidget(self.restart_btn, 0, 3)
        action_layout.addWidget(self.logs_btn, 0, 4)
        action_layout.addWidget(self.open_btn, 0, 5)
        action_layout.addWidget(self.create_btn, 0, 6)
        action_box.setLayout(action_layout)

        layout = QVBoxLayout()
        layout.addWidget(self.table)
        layout.addWidget(action_box)
        layout.addWidget(QLabel("Output"))
        layout.addWidget(self.log_view)

        container = QWidget()
        container.setLayout(layout)
        self.setCentralWidget(container)

        self.set_actions_enabled(False)
        self.refresh_instances()

        if not docker_available():
            QMessageBox.warning(
                self,
                "Docker Not Available",
                "Docker CLI not available or Docker Desktop is not running.",
            )

    def set_actions_enabled(self, enabled: bool) -> None:
        self.start_btn.setEnabled(enabled)
        self.stop_btn.setEnabled(enabled)
        self.restart_btn.setEnabled(enabled)
        self.logs_btn.setEnabled(enabled)
        self.open_btn.setEnabled(enabled)

    def log(self, message: str) -> None:
        self.log_view.appendPlainText(message)

    def refresh_instances(self) -> None:
        self.instances = self.scan_instances()
        self.table.setRowCount(len(self.instances))
        for row, instance in enumerate(self.instances):
            status = docker_status(instance.container_name)
            items = [
                QTableWidgetItem(instance.name),
                QTableWidgetItem(instance.container_name),
                QTableWidgetItem(status),
                QTableWidgetItem(instance.host_port),
                QTableWidgetItem(instance.image),
            ]
            for col, item in enumerate(items):
                item.setData(Qt.ItemDataRole.UserRole, instance.name)
                self.table.setItem(row, col, item)
        self.table.resizeColumnsToContents()
        self.set_actions_enabled(bool(self.instances))

    def scan_instances(self) -> List[InstanceInfo]:
        instances: List[InstanceInfo] = []
        if not self.instances_dir.exists():
            return instances
        for entry in sorted(self.instances_dir.iterdir()):
            if not entry.is_dir():
                continue
            env_path = entry / ".env"
            env = parse_env_file(env_path)
            container = env.get("HT_CONTAINER_NAME", "")
            host_port = env.get("HOST_PORT", "")
            image = env.get("HT_IMAGE", "")
            server_cmd = env.get("HT_SERVER_CMD", "")
            instances.append(
                InstanceInfo(
                    name=entry.name,
                    path=entry,
                    container_name=container,
                    host_port=host_port,
                    image=image,
                    server_cmd=server_cmd,
                )
            )
        return instances

    def selected_instance(self) -> Optional[InstanceInfo]:
        selected = self.table.selectedItems()
        if not selected:
            return None
        name = selected[0].data(Qt.ItemDataRole.UserRole)
        for instance in self.instances:
            if instance.name == name:
                return instance
        return None

    def on_selection_changed(self) -> None:
        self.set_actions_enabled(self.selected_instance() is not None)

    def run_compose_action(self, *args: str) -> None:
        instance = self.selected_instance()
        if not instance:
            return
        compose_file = instance.path / "docker-compose.yml"
        if not compose_file.exists():
            QMessageBox.warning(self, "Missing Compose File", "docker-compose.yml not found.")
            return
        cmd = ["docker", "compose", *args]
        self.run_command_async(cmd, instance.path)

    def fetch_logs(self) -> None:
        instance = self.selected_instance()
        if not instance:
            return
        cmd = ["docker", "compose", "logs", "--tail", "200"]
        self.run_command_async(cmd, instance.path)

    def run_command_async(self, args: List[str], cwd: Path) -> None:
        self.log(f"> {' '.join(args)} ({cwd})")
        worker = CommandWorker(args, cwd)
        worker.signals.finished.connect(self.on_command_finished)
        self.thread_pool.start(worker)

    def on_command_finished(self, code: int, stdout: str, stderr: str) -> None:
        if stdout:
            self.log(stdout.strip())
        if stderr:
            self.log(stderr.strip())
        if code != 0:
            self.log(f"Command exited with code {code}")
        self.refresh_instances()

    def open_instance_folder(self) -> None:
        instance = self.selected_instance()
        if not instance:
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(instance.path)))

    def create_instance(self) -> None:
        dialog = CreateInstanceDialog(self)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return
        values = dialog.instance_values()
        self.instances_dir.mkdir(parents=True, exist_ok=True)
        instance_dir = self.instances_dir / values["instance_name"]
        if instance_dir.exists():
            QMessageBox.warning(self, "Instance Exists", "Instance already exists.")
            return
        instance_dir.mkdir(parents=True, exist_ok=True)
        for sub in ["server", "mods", "data", "logs"]:
            (instance_dir / sub).mkdir(exist_ok=True)

        template_env_path = self.templates_dir / "instance.env"
        template_compose_path = self.templates_dir / "instance-compose.yml"
        if not template_env_path.exists() or not template_compose_path.exists():
            QMessageBox.warning(
                self,
                "Missing Templates",
                "instance.env or instance-compose.yml not found in templates/.",
            )
            return

        template_env = template_env_path.read_text(encoding="utf-8")
        template_env = template_env.replace("__INSTANCE_NAME__", values["instance_name"])
        template_env = template_env.replace("__HOST_PORT__", values["host_port"])
        template_env = template_env.replace("__SERVER_URL__", values["server_url"])
        template_env = template_env.replace("__SERVER_SHA256__", values["server_sha256"])
        if values["server_cmd"]:
            template_env = template_env.replace("HT_SERVER_CMD=", f"HT_SERVER_CMD={values['server_cmd']}")

        (instance_dir / ".env").write_text(template_env, encoding="utf-8")
        compose_dst = instance_dir / "docker-compose.yml"
        compose_dst.write_text(template_compose_path.read_text(encoding="utf-8"), encoding="utf-8")

        self.log(f"Created instance: {values['instance_name']}")
        self.refresh_instances()


def main() -> None:
    root_dir = Path(__file__).resolve().parents[1]
    app = QApplication(sys.argv)
    window = MainWindow(root_dir)
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
