import json
import sys
import zipfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

from PyQt6.QtCore import QStandardPaths, QUrl
from PyQt6.QtGui import QDesktopServices, QFont
from PyQt6.QtWidgets import (
    QApplication,
    QCheckBox,
    QDialog,
    QFileDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QPlainTextEdit,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)


TOOL_VERSION = "0.1.0"


@dataclass
class Settings:
    projects_dir: Path
    export_dir: Path
    export_zip_default: bool


def settings_path() -> Path:
    base = Path(
        QStandardPaths.writableLocation(
            QStandardPaths.StandardLocation.AppConfigLocation
        )
    )
    return base / "hytale-mod-tools" / "settings.json"


def load_settings() -> Settings:
    default_projects = Path.home() / "HytaleModProjects"
    default_exports = Path.home() / "HytaleModExports"
    path = settings_path()
    if not path.exists():
        return Settings(default_projects, default_exports, False)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return Settings(default_projects, default_exports, False)
    return Settings(
        Path(data.get("projects_dir", default_projects)),
        Path(data.get("export_dir", default_exports)),
        bool(data.get("export_zip_default", False)),
    )


def save_settings(settings: Settings) -> None:
    path = settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "projects_dir": str(settings.projects_dir),
        "export_dir": str(settings.export_dir),
        "export_zip_default": settings.export_zip_default,
    }
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_json(path: Path, payload: Dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def normalize_block_id(block_id: str) -> str:
    return block_id.replace(":", "_").replace("/", "_")


def to_list(value: str) -> List[str]:
    if not value.strip():
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


class SettingsDialog(QDialog):
    def __init__(self, parent: QWidget, settings: Settings) -> None:
        super().__init__(parent)
        self.settings = settings
        self.setWindowTitle("Settings")
        self.setModal(True)

        self.projects_dir = QLineEdit(str(settings.projects_dir))
        self.export_dir = QLineEdit(str(settings.export_dir))
        self.export_zip_default = QCheckBox("Default export as ZIP")
        self.export_zip_default.setChecked(settings.export_zip_default)

        browse_projects = QPushButton("Browse")
        browse_exports = QPushButton("Browse")
        browse_projects.clicked.connect(self.pick_projects_dir)
        browse_exports.clicked.connect(self.pick_export_dir)

        form = QFormLayout()
        row_projects = QHBoxLayout()
        row_projects.addWidget(self.projects_dir)
        row_projects.addWidget(browse_projects)
        row_exports = QHBoxLayout()
        row_exports.addWidget(self.export_dir)
        row_exports.addWidget(browse_exports)
        form.addRow("Projects directory", row_projects)
        form.addRow("Export directory", row_exports)
        form.addRow("", self.export_zip_default)

        save_btn = QPushButton("Save")
        cancel_btn = QPushButton("Cancel")
        save_btn.clicked.connect(self.accept)
        cancel_btn.clicked.connect(self.reject)

        btn_row = QHBoxLayout()
        btn_row.addStretch(1)
        btn_row.addWidget(cancel_btn)
        btn_row.addWidget(save_btn)

        layout = QVBoxLayout()
        layout.addLayout(form)
        layout.addLayout(btn_row)
        self.setLayout(layout)

    def pick_projects_dir(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "Select Projects Directory")
        if path:
            self.projects_dir.setText(path)

    def pick_export_dir(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "Select Export Directory")
        if path:
            self.export_dir.setText(path)

    def updated_settings(self) -> Settings:
        return Settings(
            Path(self.projects_dir.text().strip()),
            Path(self.export_dir.text().strip()),
            self.export_zip_default.isChecked(),
        )


class NewProjectDialog(QDialog):
    def __init__(self, parent: QWidget, settings: Settings) -> None:
        super().__init__(parent)
        self.setWindowTitle("New Project")
        self.setModal(True)

        self.project_name = QLineEdit("example-mod")
        self.base_dir = QLineEdit(str(settings.projects_dir))
        self.include_asset_pack = QCheckBox("Create asset pack")
        self.include_asset_pack.setChecked(True)
        self.include_plugin = QCheckBox("Create plugin skeleton")
        self.include_plugin.setChecked(False)

        browse_btn = QPushButton("Browse")
        browse_btn.clicked.connect(self.pick_base_dir)

        form = QFormLayout()
        form.addRow("Project name", self.project_name)
        row_dir = QHBoxLayout()
        row_dir.addWidget(self.base_dir)
        row_dir.addWidget(browse_btn)
        form.addRow("Base directory", row_dir)
        form.addRow("", self.include_asset_pack)
        form.addRow("", self.include_plugin)

        create_btn = QPushButton("Create")
        cancel_btn = QPushButton("Cancel")
        create_btn.clicked.connect(self.accept)
        cancel_btn.clicked.connect(self.reject)

        btn_row = QHBoxLayout()
        btn_row.addStretch(1)
        btn_row.addWidget(cancel_btn)
        btn_row.addWidget(create_btn)

        layout = QVBoxLayout()
        layout.addLayout(form)
        layout.addLayout(btn_row)
        self.setLayout(layout)

    def pick_base_dir(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "Select Base Directory")
        if path:
            self.base_dir.setText(path)

    def values(self) -> Dict[str, str]:
        return {
            "project_name": self.project_name.text().strip(),
            "base_dir": self.base_dir.text().strip(),
            "include_asset_pack": self.include_asset_pack.isChecked(),
            "include_plugin": self.include_plugin.isChecked(),
        }


class NewBlockDialog(QDialog):
    def __init__(self, parent: QWidget) -> None:
        super().__init__(parent)
        self.setWindowTitle("New Block")
        self.setModal(True)

        self.block_id = QLineEdit("example:block_one")
        self.display_name = QLineEdit("Example Block")
        self.description = QLineEdit("An example block")

        form = QFormLayout()
        form.addRow("Block ID", self.block_id)
        form.addRow("Display name", self.display_name)
        form.addRow("Description", self.description)

        create_btn = QPushButton("Create")
        cancel_btn = QPushButton("Cancel")
        create_btn.clicked.connect(self.accept)
        cancel_btn.clicked.connect(self.reject)

        btn_row = QHBoxLayout()
        btn_row.addStretch(1)
        btn_row.addWidget(cancel_btn)
        btn_row.addWidget(create_btn)

        layout = QVBoxLayout()
        layout.addLayout(form)
        layout.addLayout(btn_row)
        self.setLayout(layout)

    def values(self) -> Dict[str, str]:
        return {
            "block_id": self.block_id.text().strip(),
            "display_name": self.display_name.text().strip(),
            "description": self.description.text().strip(),
        }


class PluginDialog(QDialog):
    def __init__(self, parent: QWidget) -> None:
        super().__init__(parent)
        self.setWindowTitle("Generate Plugin Skeleton")
        self.setModal(True)

        self.group_id = QLineEdit("com.example.hytale")
        self.plugin_name = QLineEdit("ExamplePlugin")
        self.main_class = QLineEdit("com.example.hytale.ExamplePlugin")
        self.version = QLineEdit("0.1.0")
        self.description = QLineEdit("Example plugin")
        self.authors = QLineEdit("Example Author")

        form = QFormLayout()
        form.addRow("Group ID", self.group_id)
        form.addRow("Plugin name", self.plugin_name)
        form.addRow("Main class", self.main_class)
        form.addRow("Version", self.version)
        form.addRow("Description", self.description)
        form.addRow("Authors (comma)", self.authors)

        create_btn = QPushButton("Generate")
        cancel_btn = QPushButton("Cancel")
        create_btn.clicked.connect(self.accept)
        cancel_btn.clicked.connect(self.reject)

        btn_row = QHBoxLayout()
        btn_row.addStretch(1)
        btn_row.addWidget(cancel_btn)
        btn_row.addWidget(create_btn)

        layout = QVBoxLayout()
        layout.addLayout(form)
        layout.addLayout(btn_row)
        self.setLayout(layout)

    def values(self) -> Dict[str, str]:
        return {
            "group_id": self.group_id.text().strip(),
            "plugin_name": self.plugin_name.text().strip(),
            "main_class": self.main_class.text().strip(),
            "version": self.version.text().strip(),
            "description": self.description.text().strip(),
            "authors": self.authors.text().strip(),
        }


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.settings = load_settings()
        self.project_root: Optional[Path] = None
        self.asset_pack_root: Optional[Path] = None
        self.plugin_root: Optional[Path] = None

        self.setWindowTitle("Hytale Mod Tools")
        self.resize(1040, 720)

        self.project_path = QLineEdit("")
        self.project_path.setReadOnly(True)
        self.browse_project = QPushButton("Open Project")
        self.new_project = QPushButton("New Project")
        self.export_zip = QPushButton("Export ZIP")
        self.settings_btn = QPushButton("Settings")

        self.browse_project.clicked.connect(self.open_project)
        self.new_project.clicked.connect(self.create_project)
        self.export_zip.clicked.connect(self.export_zip_action)
        self.settings_btn.clicked.connect(self.open_settings)

        top_row = QHBoxLayout()
        top_row.addWidget(QLabel("Project"))
        top_row.addWidget(self.project_path)
        top_row.addWidget(self.browse_project)
        top_row.addWidget(self.new_project)
        top_row.addWidget(self.export_zip)
        top_row.addWidget(self.settings_btn)

        self.tabs = QTabWidget()
        self.tabs.addTab(self.asset_pack_tab(), "Asset Pack")
        self.tabs.addTab(self.plugin_tab(), "Plugin")
        self.tabs.addTab(self.help_tab(), "Help")

        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        self.log_view.setFont(QFont("Consolas", 9))

        layout = QVBoxLayout()
        layout.addLayout(top_row)
        layout.addWidget(self.tabs)
        layout.addWidget(QLabel("Output"))
        layout.addWidget(self.log_view)

        container = QWidget()
        container.setLayout(layout)
        self.setCentralWidget(container)

        ensure_dir(self.settings.projects_dir)
        ensure_dir(self.settings.export_dir)

    def log(self, message: str) -> None:
        self.log_view.appendPlainText(message)

    def open_settings(self) -> None:
        dialog = SettingsDialog(self, self.settings)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return
        self.settings = dialog.updated_settings()
        save_settings(self.settings)
        ensure_dir(self.settings.projects_dir)
        ensure_dir(self.settings.export_dir)
        self.log("Settings updated.")

    def asset_pack_tab(self) -> QWidget:
        self.ap_name = QLineEdit("Example Pack")
        self.ap_desc = QLineEdit("Example asset pack")
        self.ap_version = QLineEdit("0.1.0")
        self.ap_group = QLineEdit("com.example.hytale")
        self.ap_authors = QLineEdit("Example Author")
        self.ap_website = QLineEdit("https://example.com")
        self.ap_dependencies = QLineEdit("")
        self.ap_optional_deps = QLineEdit("")
        self.ap_load_before = QLineEdit("")
        self.ap_disabled = QCheckBox("Disabled by default")
        self.ap_includes = QCheckBox("Includes asset pack")
        self.ap_includes.setChecked(True)
        self.ap_subplugins = QLineEdit("")

        write_manifest = QPushButton("Write manifest.json")
        create_block = QPushButton("New Block")
        open_folder = QPushButton("Open asset pack folder")

        write_manifest.clicked.connect(self.write_manifest_action)
        create_block.clicked.connect(self.create_block_action)
        open_folder.clicked.connect(self.open_asset_pack_folder)

        form = QFormLayout()
        form.addRow("Name", self.ap_name)
        form.addRow("Description", self.ap_desc)
        form.addRow("Version", self.ap_version)
        form.addRow("Group", self.ap_group)
        form.addRow("Authors (comma)", self.ap_authors)
        form.addRow("Website", self.ap_website)
        form.addRow("Dependencies", self.ap_dependencies)
        form.addRow("Optional deps", self.ap_optional_deps)
        form.addRow("Load before", self.ap_load_before)
        form.addRow("Sub-plugins", self.ap_subplugins)
        form.addRow("", self.ap_disabled)
        form.addRow("", self.ap_includes)

        btn_row = QHBoxLayout()
        btn_row.addWidget(write_manifest)
        btn_row.addWidget(create_block)
        btn_row.addWidget(open_folder)
        btn_row.addStretch(1)

        box = QGroupBox("Manifest")
        box.setLayout(form)

        layout = QVBoxLayout()
        layout.addWidget(box)
        layout.addLayout(btn_row)

        widget = QWidget()
        widget.setLayout(layout)
        return widget

    def plugin_tab(self) -> QWidget:
        gen_btn = QPushButton("Generate plugin skeleton")
        open_btn = QPushButton("Open plugin folder")
        gen_btn.clicked.connect(self.generate_plugin_action)
        open_btn.clicked.connect(self.open_plugin_folder)

        layout = QVBoxLayout()
        layout.addWidget(gen_btn)
        layout.addWidget(open_btn)
        layout.addStretch(1)

        widget = QWidget()
        widget.setLayout(layout)
        return widget

    def help_tab(self) -> QWidget:
        help_text = QPlainTextEdit()
        help_text.setReadOnly(True)
        help_text.setPlainText(
            "This tool manages Hytale mod projects.\n\n"
            "- Create a new project and generate an asset pack or plugin skeleton.\n"
            "- Asset packs are generated into asset_pack/ with manifest.json and resource folders.\n"
            "- Use New Block to scaffold a block JSON + language entries.\n"
            "- Use Export ZIP to package the asset pack as a distributable file.\n\n"
            "See docs/modding for detailed references and source links."
        )
        layout = QVBoxLayout()
        layout.addWidget(help_text)
        widget = QWidget()
        widget.setLayout(layout)
        return widget

    def create_project(self) -> None:
        dialog = NewProjectDialog(self, self.settings)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return
        values = dialog.values()
        name = values["project_name"]
        base_dir = Path(values["base_dir"])
        if not name:
            QMessageBox.warning(self, "Missing Name", "Project name is required.")
            return
        ensure_dir(base_dir)
        project_root = base_dir / name
        if project_root.exists():
            QMessageBox.warning(self, "Exists", "Project folder already exists.")
            return
        project_root.mkdir(parents=True, exist_ok=True)

        project_meta = {
            "name": name,
            "created_at": datetime.utcnow().isoformat() + "Z",
            "tool_version": TOOL_VERSION,
        }
        write_json(project_root / "project.json", project_meta)

        if values["include_asset_pack"]:
            self.create_asset_pack_structure(project_root)
        if values["include_plugin"]:
            self.generate_plugin_skeleton(project_root)

        self.set_project(project_root)
        self.log(f"Created project: {project_root}")

    def open_project(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "Open Project")
        if not path:
            return
        project_root = Path(path)
        if not (project_root / "project.json").exists():
            QMessageBox.warning(self, "Invalid Project", "project.json not found.")
            return
        self.set_project(project_root)

    def set_project(self, project_root: Path) -> None:
        self.project_root = project_root
        self.asset_pack_root = project_root / "asset_pack"
        self.plugin_root = project_root / "plugin"
        self.project_path.setText(str(project_root))

    def asset_pack_manifest_path(self) -> Optional[Path]:
        if not self.asset_pack_root:
            return None
        return self.asset_pack_root / "manifest.json"

    def write_manifest_action(self) -> None:
        if not self.project_root:
            QMessageBox.warning(self, "No Project", "Open or create a project first.")
            return
        if not self.asset_pack_root:
            QMessageBox.warning(self, "No Asset Pack", "Asset pack not created for this project.")
            return
        ensure_dir(self.asset_pack_root)

        manifest = {
            "Name": self.ap_name.text().strip(),
            "Description": self.ap_desc.text().strip(),
            "Version": self.ap_version.text().strip(),
            "Group": self.ap_group.text().strip(),
            "Authors": to_list(self.ap_authors.text()),
            "Website": self.ap_website.text().strip(),
            "Dependencies": to_list(self.ap_dependencies.text()),
            "OptionalDependencies": to_list(self.ap_optional_deps.text()),
            "LoadBefore": to_list(self.ap_load_before.text()),
            "DisabledByDefault": self.ap_disabled.isChecked(),
            "IncludesAssetPack": self.ap_includes.isChecked(),
            "SubPlugins": to_list(self.ap_subplugins.text()),
        }
        write_json(self.asset_pack_root / "manifest.json", manifest)
        self.log("Wrote manifest.json")

    def create_block_action(self) -> None:
        if not self.project_root or not self.asset_pack_root:
            QMessageBox.warning(self, "No Project", "Open or create a project first.")
            return
        dialog = NewBlockDialog(self)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return
        values = dialog.values()
        block_id = values["block_id"]
        if not block_id:
            QMessageBox.warning(self, "Missing ID", "Block ID is required.")
            return
        block_file = normalize_block_id(block_id) + ".json"

        items_dir = self.asset_pack_root / "resources" / "Server" / "Item" / "Items"
        lang_dir = self.asset_pack_root / "resources" / "Server" / "Languages" / "en-US"
        items_dir.mkdir(parents=True, exist_ok=True)
        lang_dir.mkdir(parents=True, exist_ok=True)

        block_payload = {
            "Id": block_id,
            "TranslationProperties": {
                "Name": f"items.{block_id.replace(':', '.')}.name",
                "Description": f"items.{block_id.replace(':', '.')}.description",
            },
        }
        write_json(items_dir / block_file, block_payload)

        lang_path = lang_dir / "items.lang"
        name_key = f"items.{block_id.replace(':', '.')}.name"
        desc_key = f"items.{block_id.replace(':', '.')}.description"
        lines = []
        if lang_path.exists():
            lines = lang_path.read_text(encoding="utf-8").splitlines()
        lines.append(f"{name_key}={values['display_name']}")
        lines.append(f"{desc_key}={values['description']}")
        lang_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        self.log(f"Created block: {block_id}")

    def open_asset_pack_folder(self) -> None:
        if not self.asset_pack_root:
            QMessageBox.warning(self, "No Asset Pack", "Asset pack not created for this project.")
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.asset_pack_root)))

    def generate_plugin_action(self) -> None:
        if not self.project_root:
            QMessageBox.warning(self, "No Project", "Open or create a project first.")
            return
        dialog = PluginDialog(self)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return
        values = dialog.values()
        self.generate_plugin_skeleton(self.project_root, values)
        self.log("Generated plugin skeleton.")

    def open_plugin_folder(self) -> None:
        if not self.plugin_root:
            QMessageBox.warning(self, "No Plugin", "Plugin not created for this project.")
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.plugin_root)))

    def create_asset_pack_structure(self, project_root: Path) -> None:
        asset_root = project_root / "asset_pack"
        ensure_dir(asset_root)
        ensure_dir(asset_root / "resources" / "Server" / "Item" / "Items")
        ensure_dir(asset_root / "resources" / "Server" / "Languages" / "en-US")
        ensure_dir(asset_root / "resources" / "Common" / "Icons" / "Blocks")
        ensure_dir(asset_root / "resources" / "Common" / "Models" / "Blocks")
        ensure_dir(asset_root / "resources" / "Common" / "Textures" / "Blocks")

        if not (asset_root / "manifest.json").exists():
            write_json(asset_root / "manifest.json", {
                "Name": "Example Pack",
                "Description": "Example asset pack",
                "Version": "0.1.0",
                "Group": "com.example.hytale",
                "Authors": ["Example Author"],
                "Website": "",
                "Dependencies": [],
                "OptionalDependencies": [],
                "LoadBefore": [],
                "DisabledByDefault": False,
                "IncludesAssetPack": True,
                "SubPlugins": [],
            })

        items_lang = asset_root / "resources" / "Server" / "Languages" / "en-US" / "items.lang"
        if not items_lang.exists():
            items_lang.write_text("", encoding="utf-8")

    def generate_plugin_skeleton(self, project_root: Path, values: Optional[Dict[str, str]] = None) -> None:
        values = values or {
            "group_id": "com.example.hytale",
            "plugin_name": "ExamplePlugin",
            "main_class": "com.example.hytale.ExamplePlugin",
            "version": "0.1.0",
            "description": "Example plugin",
            "authors": "Example Author",
        }
        plugin_root = project_root / "plugin"
        ensure_dir(plugin_root)
        ensure_dir(plugin_root / "src" / "main" / "resources")

        package_path = values["main_class"].rsplit(".", 1)[0]
        class_name = values["main_class"].rsplit(".", 1)[-1]
        java_dir = plugin_root / "src" / "main" / "java" / Path(*package_path.split("."))
        ensure_dir(java_dir)

        settings_gradle = plugin_root / "settings.gradle.kts"
        settings_gradle.write_text(
            f"rootProject.name = \"{values['plugin_name']}\"\n",
            encoding="utf-8",
        )

        build_gradle = plugin_root / "build.gradle.kts"
        build_gradle.write_text(
            "plugins {\n"
            "    java\n"
            "}\n\n"
            "java {\n"
            "    toolchain {\n"
            "        languageVersion.set(JavaLanguageVersion.of(25))\n"
            "    }\n"
            "}\n\n"
            "repositories {\n"
            "    mavenCentral()\n"
            "}\n\n"
            "dependencies {\n"
            "    // TODO: Point this to your HytaleServer JAR.\n"
            "    compileOnly(files(\"/path/to/HytaleServer.jar\"))\n"
            "}\n",
            encoding="utf-8",
        )

        java_file = java_dir / f"{class_name}.java"
        java_file.write_text(
            "package " + package_path + ";\n\n"
            "public class " + class_name + " {\n"
            "    public void onEnable() {\n"
            "        // TODO: Register events and startup logic.\n"
            "    }\n\n"
            "    public void onDisable() {\n"
            "        // TODO: Cleanup.\n"
            "    }\n"
            "}\n",
            encoding="utf-8",
        )

        manifest = {
            "Name": values["plugin_name"],
            "Version": values["version"],
            "MainClass": values["main_class"],
            "Description": values["description"],
            "Authors": to_list(values["authors"]),
        }
        write_json(plugin_root / "src" / "main" / "resources" / "manifest.json", manifest)

    def export_zip_action(self) -> None:
        if not self.asset_pack_root:
            QMessageBox.warning(self, "No Asset Pack", "Asset pack not created for this project.")
            return
        if not self.asset_pack_root.exists():
            QMessageBox.warning(self, "Missing Folder", "asset_pack folder not found.")
            return

        default_name = self.asset_pack_root.name + ".zip"
        target = self.settings.export_dir / default_name
        if not self.settings.export_zip_default:
            path, _ = QFileDialog.getSaveFileName(
                self,
                "Export Asset Pack ZIP",
                str(target),
                "ZIP Files (*.zip)",
            )
            if not path:
                return
            target = Path(path)

        ensure_dir(target.parent)
        with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as zip_file:
            for file_path in self.asset_pack_root.rglob("*"):
                if file_path.is_file():
                    arcname = file_path.relative_to(self.asset_pack_root)
                    zip_file.write(file_path, arcname)
        self.log(f"Exported ZIP: {target}")


def main() -> None:
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
