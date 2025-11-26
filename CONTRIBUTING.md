# Contributing to Community-Scripts

Thank you for your interest in contributing to **Hudu Community Scripts**!  
This repository serves as a **meta-repository** that organizes a collection of independent community projects via **git submodules**.

You can contribute in **three primary ways**:

1. By submitting pull requests to this meta-repo  
2. By contributing directly to the individual submodule repositories  
3. By posting ideas, scripts, and feedback on the Hudu Community site  

---

## Ways to Contribute

### 1. Contributing to the Meta-Repository (This Repo)

Use this method if you are:
- Adding a **new category**
- Registering a **new submodule**
- Updating **README links or organization**
- Improving documentation or structure

**Workflow:**
1. Fork the repository  
2. Create a feature branch  
3. Make your changes  
4. Open a Pull Request against `main`

> This repository **does not accept direct code changes** to projects that live inside submodules. Those must be submitted to the submodule repository itself.

---

### 2. Contributing to a Submodule Repository

Each project listed here is its **own independent GitHub repository**.

If you're fixing a bug, adding features, or improving scripts:
- Navigate to the specific submodule’s GitHub repository
- Fork / clone that repository
- Submit your Pull Request there

Once approved, the maintainers will update the submodule pointer in this meta-repo.

> Pull requests that modify submodule contents directly in this repo **will be closed**, since the submodule commit pointer is only updated after upstream approval.

---

### 3. Community Contributions (No Git Required)

You can also contribute without GitHub by posting directly to:

👉 **https://community.hudu.com**

Good uses of the community board include:
- Script ideas
- Feature requests
- Usage examples
- Troubleshooting help
- Sharing automation workflows

The Hudu team and community maintainers actively monitor the community board and promote successful contributions into official repos.

---

## Contribution Standards

To help keep everything usable and production-safe:

- Scripts must be **non-destructive by default**
- All tools must include:
  - Clear usage instructions
  - Parameter documentation
  - Basic validation and safeguards
- API-based scripts must:
  - Use environment variables or secure prompts for secrets
  - Avoid hard-coded credentials
- PowerShell scripts should be compatible with **PowerShell 7+**
- Python tools should include a `requirements.txt` or `pyproject.toml`

---

## Adding a New Submodule

If you are submitting a brand new community project:
1. Create a public GitHub repository under your account or the Hudu org
2. Ensure it includes:
   - A README
   - License (MIT preferred)
   - Basic usage docs
3. Open a PR to this repo requesting it be added as a submodule
4. A maintainer will:
   - Review the project
   - Add it as a submodule
   - Register it in the main README

---

## Licensing

Each submodule repository maintains its **own license**, which applies only to that project.

The meta-repository (`Community-Scripts`) is for **organization and discovery only** and does not override the licenses of embedded projects.

---

## Questions?

- GitHub Discussions / Issues (per project)
- Community Board: **https://community.hudu.com**
- Or open a documentation PR here

We appreciate every contribution — from scripts to feedback to documentation improvements.  
Thank you for helping grow the Hudu community! 🚀
