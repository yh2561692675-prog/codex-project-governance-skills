# 项目开发治理 Skills

一组可复用的 Codex Skill，用来让项目开发可审计、可界定、可恢复。它们重点处理那些容易“说完成”却难以证明的环节：确认真实检出目录、保持证据来源、执行风险门禁、安全恢复长任务，以及把本地工程完成与人工验收、正式发布分开。

这是独立开源项目，不是 OpenAI 产品，不会授予 Codex 或 API 使用权限，也不保证任何项目、仓库或计划申请通过。

## 包含内容

| Skill | 用途 |
|---|---|
| `x-project-development-preflight` | 绑定真实 X 盘 Git 根/worktree、项目 profile、分支、写入者和证据身份。 |
| `project-design-plan-readiness` | 在编码前检查设计文档和按依赖排序的实施计划是否完整。 |
| `lightweight-project-governance` | 处理本地自治、审核、升级和风险分层，避免静默扩大范围。 |
| `long-running-project-execution` | 按已批准计划执行、写检查点、约束模型路由并在阻塞时安全停止。 |
| `evidence-bound-project-closure` | 生成分层结项报告，区分工程、安装、真实使用、人工验收、正式数据和发布。 |
| `animate-tech-board` | 媒体工作流可选的视觉板素材；同样遵循可安装目录契约。 |

## 要求

- Windows，支持 Windows PowerShell 5.1 或 PowerShell 7。
- 一个包含治理 Skill 的 Git worktree。预检 Skill 需要目标项目提供自己的 profile 和入口/合规检查。
- 由用户选择的 Codex Skill 安装目录。安装器不会修改全局 `CODEX_HOME`、密钥或无关目录。

本版本不声明支持 Linux 或 macOS；新增跨平台支持必须配套独立 CI 测试矩阵。

## 从仓库安装一个 Skill

在仓库根目录运行，替换为上表中的任意 Skill 名称：

```powershell
$skillName = 'x-project-development-preflight'
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$installPath = Join-Path $codexHome "skills\$skillName"
$evidencePath = Join-Path $codexHome "skill-install-evidence\$skillName"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexSkillPackage.ps1 `
  -SourceSkillPath ".\skills\$skillName" `
  -InstalledSkillPath $installPath `
  -EvidencePath $evidencePath
```

安装器会先打包、暂存并校验 parity，再切换目标目录；已有安装会被移动到可恢复备份。证据目录采用只创建策略，若已存在则阻止操作。

## 验证和卸载

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-SkillPackageLayout.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SkillInstallation.ps1
```

卸载时提供新的备份目录和证据目录，安装目录会被移动而不是直接删除：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-CodexSkillPackage.ps1 `
  -InstalledSkillPath $installPath `
  -BackupPath (Join-Path $codexHome "skills-backups\$skillName-manual") `
  -EvidencePath (Join-Path $codexHome "skill-uninstall-evidence\$skillName-manual")
```

## 证据分层

项目分别报告以下层次：

1. 工程实现与自动化测试。
2. 全新安装与源/安装逐文件 SHA-256 parity。
3. 绑定具体项目/worktree 的本地真实使用。
4. 人工验收和审核决定。
5. 正式数据或组织签署。
6. 公开发布和独立采用。

测试通过、fixture、候选包或一次演示不能替代后续层次。身份、所有权、证据或必需人工决定未知时，Skill 默认安全阻断。

## 贡献

提交 Issue 或 PR 前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)、[SECURITY.md](SECURITY.md) 和 [docs/maintenance.md](docs/maintenance.md)。行为变更必须有聚焦测试和简短证据说明；不得提交 API key、Cookie、个人数据、本地绝对路径或生成的安装目录。

## 许可证

本项目采用 [MIT License](LICENSE)。

## 路线图

- 经维护者审核后发布许可证和版本化发行版。
- 用可复现 manifest 建立独立公开使用案例。
- 只有在具备原生 CI 证据后才增加跨平台支持。
- 核心安装和治理契约稳定后再增加插件集成。

## 状态

此公开仓库包含 V2.0 治理集成和可移植安装加固，当前为预发布候选：不声明版本标签、GitHub Release、外部采用、人工验收或项目申请通过。
