# NVIDIA Tesla P40 WDDM Feature-Gate Bypass (Drivers 551.86+)

> **Research & Proof of Concept (PoC)** to enable WDDM (Windows Display Driver Model) mode on NVIDIA Tesla P40 GPUs on driver branches 551.86 and above, overcoming the Windows **Error 43** initialization barrier without losing hardware identification or display functionality.

---

## ⚠️ Legal & Ethical Disclaimer
* This repository contains **NO proprietary NVIDIA binary code or copyright-protected driver files**.
* It provides strictly **open-source patching instructions, automated offset-patching scripts, and reverse-engineering research documentation**.
* This project is a **Proof of Concept (PoC)** created for educational, research, and hardware-interoperability purposes to utilize modern driver features on Pascal GPUs that still retain core hardware support in these drivers.
* Use this at your own risk. Modifying kernel-mode drivers requires Windows Test Mode and disabling WHQL signature verification checks.

---

## 🎯 Background & The "Error 43" Problem
Up to driver version **551.61**, enabling WDDM on the Tesla P40 (GP102 core, 24 GB VRAM) was achievable simply by setting Registry values (`AdapterType=1`, `GridLicensedFeatures=7`).

Starting with driver version **551.86**, NVIDIA introduced a programmatic feature-gate (softlock) in the kernel driver (`nvlddmkm.sys`):
1. **The Registry keys are still read correctly**, setting internal configuration flags.
2. Downstream in the Resource Manager, the driver encounters a new conditional branch evaluating display licensing.
3. If the GPU is a Tesla device attempting WDDM initialization without an active enterprise GRID license, the driver aborts with kernel status `-0x3fe1fff7`, resulting in **Windows Error 43**.
4. **Why previous global signature patches failed:** Blanket replacing `MOV EAX, 0x56` with `0x00` corrupted 138 unrelated functions across the 60 MB binary and broke device string descriptors, causing the GPU to be recognized only as a generic broken device named **"NVxx"**.

---

## 🔬 Reverse-Engineering Findings & Discovery

Using **Ghidra 12.2** (automated via Ghidra headless scripts and Version Tracking against 551.61):

### 1. The Engineering Artifact: `AllowWddmOnTesla`
Inside `nvlddmkm.sys`, an embedded Unicode string was identified at Virtual Address `143a33d20`:
```text
u"AllowWddmOnTesla"
```
This parameter is read by `FUN_143a2e330` and sets a global internal byte flag at `DAT_140eeeed9`. However, a loop-index limit in that function cuts off standard evaluation.

### 2. The Execution Gate: `FUN_1414375a0`
Cross-referencing `DAT_140eeeed9` revealed the exact gate evaluating this setting during hardware display pipeline setup:
```assembly
1414384f2: 44 38 35 E0 69 AB FF    CMP byte ptr [DAT_140eeeed9], R14B  ; Is AllowWddmOnTesla == 0?
1414384f9: 41 8B CD                MOV ECX, R13D
1414384fc: 0F 85 54 01 00 00       JNZ LAB_141438656                   ; JUMP TO SUCCESS IF ALLOWED!
```
* **Default Path (`AllowWddmOnTesla == 0`):** Falls through into `FUN_14001bcd0(..., 0x20808161, ...)`. Failing that check immediately returns `-0x3fe1fff7` -> **Error 43**.
* **Patched Path:** Modifying the conditional jump `JNZ` into an unconditional jump `JMP` (`E9 55 01 00 00 90`) forces the driver to **always take the success branch to `141438656`**, cleanly bypassing the check.

---

## 🛠️ The Surgical 2-Point Patch

By combining this with the primary display initialization entry gate in `PAGE_DD`, **only 6 bytes** are changed in the entire 60 MB binary:

| Gate | Target Function | Virtual Address (VA) | File Offset (551.86) | Original Bytes | Patched Bytes | Purpose |
|---|---|---|---|---|---|---|
| **Gate 1** | Display Driver Init | `140274f3f` | `0x27473F` | `B8 56 00 00 00` | `B8 00 00 00 00` | `MOV EAX, 0x0` (Bypass display subsystem gate) |
| **Gate 2** | `FUN_1414375a0` | `1414384fc` | `0x1328EFC` | `0F 85 54 01 00 00` | `E9 55 01 00 00 90` | `JMP 0x141438656; NOP` (Force WDDM permission) |

---

## 📦 Verified Target Driver & Hashes

This Proof of Concept was developed and verified against the following package:

* **Official Installer:** `551.86-notebook-win10-win11-64bit-international-nsd-dch-whql.exe`
  * **Size:** 665,416,840 bytes
  * **SHA256:** `114ede1f774cebdf3fb2984788db4a27ba59ee6dbc3b187b0cdece42d49fdc8d`
* **Original Kernel Driver (`nvlddmkm.sys`):**
  * **Size:** 59,971,208 bytes
  * **SHA256:** `fb58c7216cb6784f71299643c20fb585d36988091d3b69173d77c4f0846367ef`
* **Patched Kernel Driver (`nvlddmkm.sys`):**
  * **SHA256:** `a9b021b3b5902b4223fedba8dbf27cc802342457ed0235bcfbcbcc89978dbab6`

---

## 🚀 How to Reproduce (Step-by-Step)

### Step 1: Enable Windows Test Mode
Since the driver binary will be modified, Windows must allow self-signed test certificates.
Open Command Prompt as **Administrator**:
```cmd
bcdedit /set testsigning on
```
*Reboot your PC.*

### Step 2: Unpack the Driver
Use **7-Zip** to extract `551.86-notebook-win10-win11-64bit-international-nsd-dch-whql.exe` into a working folder.

### Step 3: Run the Surgical Patcher
Copy `patch_p40_wddm.py` into your working folder and run:
```cmd
python patch_p40_wddm.py "Display.Driver\nvlddmkm.sys" "Display.Driver\nvlddmkm.sys"
```
*(Exactly 6 bytes will be modified; original file size and PE headers remain 100% intact.)*

### Step 4: Self-Sign the Driver
Run the provided PowerShell script as **Administrator**:
```powershell
powershell -ExecutionPolicy Bypass -File .\sign_driver.ps1 -DriverDir "Display.Driver"
```
This automatically creates a trusted test certificate (`CN=nv_mod`) in your local machine store and signs both `nvlddmkm.sys` and `nv_disp.cat`.

### Step 5: Install via Device Manager
1. Open **Device Manager** (`Win + X` -> Device Manager).
2. Expand **Display adapters**, right-click **NVIDIA Tesla P40** -> **Update driver**.
3. Select **Browse my computer for drivers** -> **Let me pick from a list...** -> **Have Disk...**.
4. Browse to your `Display.Driver` folder, choose the INF file (e.g. `nv_dispi.inf` or `nvacc.inf`), and confirm installation when Windows prompts about the test certificate.

### Step 6: Enable WDDM in the Registry
Run `enable_wddm.bat` as **Administrator**. It automatically locates the GPU Class subkey and sets:
* `AdapterType = 1`
* `EnableMsHybrid = 1`
* `GridLicensedFeatures = 7`
* `AllowWddmOnTesla = 1`

### Step 7: Verification
Run `nvidia-smi` in terminal:
```text
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 551.86                 Driver Version: 551.86         CUDA Version: 12.4     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                     TCC/WDDM  | Bus-Id          Disp.A | Volatile Uncorr. ECC |
|=========================================+========================+======================|
|   0  Tesla P40                    WDDM  |   00000000:01:00.0 Off |                  Off |
+-----------------------------------------+------------------------+----------------------+
```

---

## 🤝 Community Invitation & Porting to Newer Drivers
This repository proves that Pascal GP102 silicon can run modern driver branches in WDDM display mode.
Everyone in the reverse-engineering and home-lab community is warmly invited to fork and port these findings to newer driver releases (560.x, 570.x, 580.x). Look for the `AllowWddmOnTesla` string and the conditional branch leading to `return -0x3fe1fff7;` in Ghidra.

---

## 🧠 Credits & Research Breakdown
* **Disassembly & Decompilation:** Ghidra 12.2 Public (NSA).
* **Research & AI Collaboration Assistance:**
  * **~75%:** Standard Web AI Chat (www.google.de AI chat assistant) for interactive decompilation interpretation, control flow mapping, and Ghidra exploration.
  * **~20%:** Claude Sonnet 5.5 / Claude Opus for structural analysis and sanity checks.
  * **~5%:** Antigravity (AGY) CLI powered by Gemini 3.8 Flash (Low/Medium) for workspace automation, file inspection, and script generation.
* **Human Investigator:** At the end, the string `AllowWddmOnTesla` was discovered and tied directly to the bypass jump!
* **Summary & Repository Packaging:** Compiled and formatted via Gemini 3.8 Flash with AGY.
