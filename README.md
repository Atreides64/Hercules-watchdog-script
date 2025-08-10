## Scheduled Task Setup

To run the watchdog script automatically at startup and keep it running:

1. Open **Task Scheduler** (search in Start Menu)

2. Click **Create Task...**

3. Under the **General** tab:
   - Name it `Watchdog Service`
   - Select **Run whether user is logged on or not**
   - Check **Run with highest privileges**
   - Configure for your Windows version (e.g., Windows 10 or Windows 11)

4. Under the **Triggers** tab:
   - Click **New...**
   - Begin the task: **At startup**
   - Click OK

5. Under the **Actions** tab:
   - Click **New...**
   - Action: **Start a program**
   - Program/script: `powershell.exe`
   - Add arguments: `-NoProfile -ExecutionPolicy Bypass -File "C:\Path\To\check-services.ps1"`
     (Replace `"C:\Path\To\check-services.ps1"` with your actual script path)

6. Under the **Conditions** tab:
   - Adjust based on your preferences (e.g., uncheck "Start the task only if the computer
