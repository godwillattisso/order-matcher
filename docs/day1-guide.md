# Day 1: Toolchain + C++ Reference Model (Order Matching Engine)

**By the end of today you will have:**
1. Vivado installed and proven to run **UVM** and **DPI-C** (the two things that can kill this project).
2. The C++ reference order book compiled and passing its tests.
3. The C++ model called from SystemVerilog (the Day 4 scoreboard hookup, de-risked now).
4. A test plan, and everything pushed to GitHub.

**Starting point:** `order-matcher-day1.zip` (sent with this guide). It has all of today's code already written and tested. Your job today is to install the tools, run it, and **read and understand each file**. You'll be asked about the C++ model in interviews.

**Assumptions. Stop and tell me if any are wrong:**
- You're on a **Windows 10/11** laptop. (Every command below is for Windows.)
- You have **~60 GB free disk space** and an internet connection that can download ~15-25 GB.
- You have, or can create, a free **AMD account** and a **GitHub account**.
- The Basys3 board is **not needed today**.

---

## Apps you'll use today

| App | What it's for | Where you'll type |
|---|---|---|
| **Vivado 2025.2** (free ML Standard) | Simulator (xvlog/xelab/xsim), later synthesis + programming the board | Windows **Command Prompt** (not PowerShell) |
| **VS Code** | Where you write and read all code (`.sv`, `.cpp`, `.md`) | VS Code editor |
| **MSYS2 (UCRT64)** | A `g++` compiler to build and run the C++ model on its own | The **MSYS2 UCRT64** terminal |
| **Git for Windows** | Version control, push to GitHub | VS Code's built-in terminal or Git Bash |

**Why Vivado 2025.2 and not 2026.1:** starting with 2026.1, AMD's free tier became "Basic" and needs a license file you renew every year. 2025.2 is the last version that needs no license at all. It fully supports the Basys3's chip (XC7A35T), and it's what AMD's simulator docs (UG900) are written for.

---

## Step 1: Start the Vivado download (do this first; it takes 1-3 hours)

1. Go to **https://www.xilinx.com/support/download.html** (it redirects to AMD).
2. In the left version list, click **2025.2**.
3. Under "Vivado Edition - 2025.2 Full Product Installation", download the **Windows Self Extracting Web Installer** (a ~200 MB `.exe`).
4. Sign in with your AMD account when asked (create one if needed; it's free). You may have to fill in a short export-compliance form with your name and address. That's normal.
5. Run the `.exe`. If Windows asks for permission, click **Yes**.
6. In the installer:
   - Sign in with your AMD account again → choose **Download and Install Now**.
   - **Select Product:** `Vivado`.
   - **Select Edition:** `Vivado ML Standard` (the free one).
   - **Customize:** under **Devices**, uncheck everything except **7 Series** (Artix-7 is inside it). Leave **Design Tools → Vivado Design Suite** checked. Make sure **Install Cable Drivers** is checked (you need it on Day 6 for the board). You can uncheck Vitis/Vitis HLS if they appear, to save space.
   - Accept all licence agreements.
   - **Install directory:** keep the default and **write it down** (usually `C:\AMDDesignTools` or `C:\Xilinx`). You need it in Step 5.
7. Click **Install** and let it run. Do Steps 2-4 while you wait.

---

## Step 2: Install the other apps (while Vivado downloads)

### 2a. VS Code
1. Download from **https://code.visualstudio.com** → install with defaults. On the "Select Additional Tasks" screen, tick **Add "Open with Code" action** for files and folders.
2. Open VS Code → click the **Extensions** icon on the left bar (four squares) → search and install:
   - **SystemVerilog - Language Support** or **Verilog-HDL/SystemVerilog/Bluespec SystemVerilog** (by mshr-h): syntax highlighting for `.sv`.
   - **C/C++** (by Microsoft): highlighting for `.cpp`.

### 2b. Git for Windows
1. Download from **https://git-scm.com/download/win** → install with defaults.
2. Open **Command Prompt** (Start menu → type `cmd` → Enter) and set your identity once:
   ```
   git config --global user.name "Godwill <your last name>"
   git config --global user.email "<the email on your GitHub account>"
   ```

### 2c. MSYS2 (gives you `g++`)
1. Download the installer from **https://www.msys2.org** → install to the default `C:\msys64`.
2. When it finishes, open **"MSYS2 UCRT64"** from the Start menu (purple/orange icon labelled UCRT64; **not** MSYS2 MSYS or MINGW64).
3. In that terminal, run:
   ```
   pacman -S --needed mingw-w64-ucrt-x86_64-gcc
   ```
   Press **Enter** to accept, then **Y**.
4. Check it:
   ```
   g++ --version
   ```
   You should see a version number (14.x or newer).

> ⚠️ **Do NOT add `C:\msys64\ucrt64\bin` to your Windows PATH.** Vivado's simulator uses its own built-in compiler. If MSYS2's DLLs are on PATH, the simulator can load the wrong `libstdc++` DLL and crash when it runs your C++. Only use `g++` from inside the MSYS2 UCRT64 terminal.

---

## Step 3: Set up the project folder and GitHub repo

1. Create the folder **`C:\dev`** (File Explorer → `C:` → right-click → New → Folder).
   *Why not Desktop or Documents:* Vivado tools break on paths with **spaces**, and OneDrive syncing Desktop/Documents causes file-lock errors during simulation.
2. Unzip `order-matcher-day1.zip` into `C:\dev`, so you end up with **`C:\dev\order-matcher\model\ref_book.cpp`** (check there's no extra nested `order-matcher\order-matcher`).
3. Open VS Code → **File → Open Folder** → pick `C:\dev\order-matcher`. Click "Yes, I trust the authors" if asked.
4. You should see:
   ```
   order-matcher/
     model/      ref_book.h, ref_book.cpp      ← the C++ reference order book
                 dpi_ref_book.cpp              ← lets SystemVerilog call it
                 test_ref_book.cpp             ← standalone tests
     tb/sanity/  hello_uvm.sv                  ← Check 1: UVM works
                 hello_dpi.c, hello_dpi.sv     ← Check 2: DPI-C works
                 tb_ref.sv                     ← Check 3: SV calls the real C++ model
     docs/       test_plan.md
     rtl/ scripts/ fpga/                       ← empty for now (Days 2-6)
     .gitignore                                ← keeps simulator junk out of Git
   ```
5. Create the GitHub repo: on **github.com** → **New repository** → name `order-matcher` → **Public** → do **not** add a README or .gitignore (you already have one) → **Create repository**. Leave that page open; it shows the repo URL.
6. In VS Code open a terminal: **Terminal → New Terminal** (it opens at `C:\dev\order-matcher`). Run:
   ```
   git init
   git add .
   git commit -m "Day 1: C++ reference model, sanity tests, test plan"
   git branch -M main
   git remote add origin https://github.com/<your-username>/order-matcher.git
   git push -u origin main
   ```
   A browser window pops up to sign in to GitHub the first time. That's expected.

---

## Step 4: Build and test the C++ reference model (no Vivado needed)

**Where:** the **MSYS2 UCRT64** terminal.

1. Go to the model folder (MSYS2 writes `C:\` as `/c/`):
   ```
   cd /c/dev/order-matcher/model
   ```
2. Compile:
   ```
   g++ -std=c++14 -Wall -o test_ref_book test_ref_book.cpp ref_book.cpp
   ```
   No output = success. It creates `test_ref_book.exe`.
3. Run:
   ```
   ./test_ref_book.exe
   ```
4. **Expected output:**
   ```
   test_rest_on_empty_book
   ...
   test_random_invariants
     outcomes: 7587 filled, 8390 rested, 4023 rejected
   ALL TESTS PASSED
   ```

**Now read the code in VS Code (spend real time here; budget about 1 hour):**
- `ref_book.h`: the data layout. 16 price levels per side, each a `std::deque` (a FIFO queue). The front of the queue is the oldest order, which gives you **time priority** for free. This is the same structure the RTL will use on Day 2 (16 levels × 4-deep FIFO).
- `ref_book.cpp` → `submit()`: the whole matching algorithm in ~30 lines. Trace `test_sweep_levels` by hand on paper.
- `test_ref_book.cpp`: 7 directed tests (one per rule) plus a **random test** that fires 20,000 orders and checks rules that must *always* hold, for example "the book is never crossed". Those always-true rules become your SystemVerilog assertions on Day 5.

**One thing the code taught us:** a rejected order (`REJECT_FULL`) can **never** have traded first. If the order's own price level is full, there are resting orders on the same side at that price, so nothing on the other side can cross it. The random test checks this. Put it in your interview notes; it's the kind of reasoning DV interviewers look for.

---

## Step 5: Open a Vivado command-line window

Wait for the Vivado install to finish. You'll run the simulator from the command line, not the Vivado GUI. That's how DV engineers work, and it's what your regression script will do on Day 5.

1. Find `settings64.bat`: File Explorer → open the install directory from Step 1.6 → `2025.2` → `Vivado` → you should see `settings64.bat`. Typical full path:
   `C:\AMDDesignTools\2025.2\Vivado\settings64.bat` or `C:\Xilinx\Vivado\2025.2\settings64.bat`.
   Click the address bar and copy the folder path.
2. Open **Command Prompt** (Start → `cmd`). **Not PowerShell**, because `.bat` setup scripts don't carry over to PowerShell.
3. Run it, with quotes around the path:
   ```
   "C:\AMDDesignTools\2025.2\Vivado\settings64.bat"
   ```
4. Check it worked:
   ```
   xvlog -version
   ```
   You should see `Vivado Simulator v2025.2`.

> You have to repeat steps 2-3 **every time you open a new Command Prompt**. (On Day 5 the Python regression script will do it for you.)

**The 3 simulator commands you'll use all week:**
| Command | What it does | Like... |
|---|---|---|
| `xvlog` | Compiles `.sv` files | `g++ -c` |
| `xelab` | Links ("elaborates") them into a simulation snapshot | the linker |
| `xsim` | Runs the snapshot | running the `.exe` |
| `xsc` | Compiles C/C++ into a library the simulator can call (DPI) | `g++ -shared` |

---

## Step 6: Check 1, UVM runs

In the same Command Prompt:
```
cd C:\dev\order-matcher
mkdir sim\uvm_hello
cd sim\uvm_hello
xvlog -sv -L uvm ..\..\tb\sanity\hello_uvm.sv
xelab tb_hello_uvm -L uvm -relax -s hello_uvm_sim
xsim hello_uvm_sim -runall
```
- `-L uvm` tells the tools to use the UVM library that ships with Vivado.
- Each test runs in its own folder under `sim\`, because the tools dump files (`xsim.dir`, `.log`, `.jou`) wherever you run them. `sim\` is in `.gitignore`.

**Pass looks like:**
```
UVM_INFO ... [HELLO] UVM is working in the Vivado simulator
...
--- UVM Report Summary ---
UVM_ERROR :    0
UVM_FATAL :    0
```

---

## Step 7: Check 2, DPI-C runs (SystemVerilog calls C)

```
cd C:\dev\order-matcher
mkdir sim\dpi_hello
cd sim\dpi_hello
xsc ..\..\tb\sanity\hello_dpi.c
xvlog -sv ..\..\tb\sanity\hello_dpi.sv
xelab tb_hello_dpi -sv_lib dpi -s hello_dpi_sim
xsim hello_dpi_sim -runall
```
- `xsc` builds a library named `dpi` inside `xsim.dir`. `-sv_lib dpi` tells `xelab` to link it.

**Pass:** `DPI PASSED: 2 + 3 = 5`

---

## Step 8: Check 3, SystemVerilog calls the real C++ order book

This is the biggest risk check of the week. It proves that **C++** (not just C) works through DPI in your Vivado.
```
cd C:\dev\order-matcher
mkdir sim\ref_model
cd sim\ref_model
xsc ..\..\model\ref_book.cpp ..\..\model\dpi_ref_book.cpp
xvlog -sv ..\..\tb\sanity\tb_ref.sv
xelab tb_ref -sv_lib dpi -s ref_sim
xsim ref_sim -runall
```
**Pass:**
```
order 1 (BUY 5 @ 10):  0 trades, status 0 (0 = rested)
order 2 (SELL 8 @ 9):  1 trades, status 0 (0 = rested)
  trade 0: buy_id=1 sell_id=2 price=10 qty=5
REF MODEL DPI PASSED
```
Read `dpi_ref_book.cpp` and `tb_ref.sv` side by side. Notice:
- `extern "C"` stops C++ from renaming ("mangling") the functions, so the simulator can find them by name.
- `DPI_DLLESPEC` marks each function as exported from the Windows DLL. Without it, `xelab` reports "undefined DPI function".
- An SV `output int` argument becomes an `int*` in C.

---

## Step 9: Review the test plan

Open `docs/test_plan.md` in VS Code. It's filled in with the rules, sequences, assertions and coverage goals. Read it and change anything you disagree with. It is the contract for Days 3-5. If a recruiter asks "how did you decide what to verify?", this document is your answer.

---

## Step 10: Commit

In the VS Code terminal:
```
git add .
git commit -m "Day 1: toolchain verified (UVM, DPI-C, C++ model via DPI)"
git push
```

---

## If something breaks

| Symptom | Likely cause → fix |
|---|---|
| `'xvlog' is not recognized` | You didn't run `settings64.bat` in **this** Command Prompt, or you're in PowerShell. Use `cmd`, then rerun Step 5.3. |
| `xvlog` errors on a path | The path has a space or is under OneDrive. Use `C:\dev\order-matcher`. |
| `Failed to find design unit uvm_pkg` | Missing `-L uvm` on `xvlog` **and** `xelab`. |
| `xelab`: undefined DPI import function | `xsc` wasn't run in the **same folder**, or `DPI_DLLESPEC` / `extern "C"` was removed. |
| Check 2 passes but Check 3 crashes | MSYS2 was added to Windows PATH (see Step 2c warning). Remove it from PATH and open a new Command Prompt. |
| `g++: command not found` | You're in the wrong MSYS2 terminal. Use **MSYS2 UCRT64**. |
| Check 3 still fails after all that | Use the **fallback** from the plan: the C++ writes expected trades to a file and the scoreboard reads the file. Send me the error first. It's usually fixable. |

---

## End-of-day checklist
- [ ] `ALL TESTS PASSED` from the C++ model (Step 4)
- [ ] UVM hello world: `UVM_ERROR : 0` (Step 6)
- [ ] `DPI PASSED` (Step 7)
- [ ] `REF MODEL DPI PASSED` (Step 8)
- [ ] Test plan reviewed (Step 9)
- [ ] Pushed to GitHub (Step 10)
- [ ] You can explain on a whiteboard how `submit()` handles a buy that sweeps 2 price levels

**Day 2 preview:** RTL for the book memory (16 levels × 4-deep FIFOs per side) and the priority encoders that find the best bid and best ask. These mirror `bids_[]`, `asks_[]`, `best_bid()` and `best_ask()` in your C++ model.
