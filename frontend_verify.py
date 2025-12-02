from playwright.sync_api import Page, expect, sync_playwright
import re

def verify_frontend(page: Page):
    page.on("console", lambda msg: print(f"Browser Console: {msg.text}"))
    page.on("pageerror", lambda exc: print(f"Browser Error: {exc}"))

    page.goto("http://localhost:8081")

    # Login
    try:
        login_modal = page.get_by_text("Connect Login", exact=True)
        if login_modal.is_visible(timeout=3000):
            with open("recovery.txt", "r") as f:
                content = f.read()
                match = re.search(r"Password:\s+(\S+)", content)
                if match:
                    pwd = match.group(1)
                    page.get_by_placeholder("Password").fill(pwd)
                    page.get_by_role("button", name="Sign In").click()
                    expect(login_modal).not_to_be_visible()
    except Exception:
        pass

    # Seed data
    token = page.evaluate("sessionStorage.getItem('connect_auth')")
    if token:
        page.context.request.post("http://localhost:8081/api/workspaces",
            data={"name": "Test Space"},
            headers={"Authorization": f"Bearer {token}"}
        )

    page.reload()

    # Debug screenshot
    page.screenshot(path="/home/jules/verification/debug_state.png")

    # Try to verify Remember button existence directly (maybe it's there even if sidebar is broken?)
    # No, remember button is in Chat view which needs thread selected.
    # Thread creation needs sidebar.

    expect(page.get_by_text("Connect v2.0")).to_be_visible()

    # Try creating thread via API
    if token:
        # Get workspace ID
        ws_resp = page.context.request.get("http://localhost:8081/api/workspaces", headers={"Authorization": f"Bearer {token}"})
        ws_data = ws_resp.json()
        if ws_data.get('workspaces') and len(ws_data['workspaces']) > 0:
            ws_id = ws_data['workspaces'][0]['id']
            # Create thread
            t_resp = page.context.request.post("http://localhost:8081/api/threads",
                data={"workspace_id": ws_id, "name": "API Thread"},
                headers={"Authorization": f"Bearer {token}"}
            )
            t_data = t_resp.json()
            thread_id = t_data.get('id')

            # Now reload and select thread?
            # Or just check if thread appears in sidebar
            page.reload()
            # Click the thread in sidebar
            page.get_by_text("API Thread").click()

            # Now check Remember button
            expect(page.get_by_role("button", name="Remember")).to_be_visible()

            # Click it to test
            # page.get_by_role("button", name="Remember").click()
            # Expect "Thread summarized" alert or similar? (Handled by alert listener usually)

            # Check Peer Network
            page.get_by_text("Peer Network").click()
            expect(page.get_by_text("Peer Network", exact=True)).to_be_visible()

            page.screenshot(path="/home/jules/verification/frontend_verify.png")
            return

    # If we are here, something failed
    print("Failed to seed thread or login")

if __name__ == "__main__":
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        try:
            verify_frontend(page)
        except Exception as e:
            print(f"Verification failed: {e}")
            page.screenshot(path="/home/jules/verification/frontend_error.png")
            raise e
        finally:
            browser.close()
