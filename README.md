# crm-hygiene-automation

Automated data pipeline for monitoring CRM hygiene, applying business rules, and delivering actionable insights to Sales Managers.

---

## Architecture Overview

The automation runs on a decoupled, three-tier architecture:

1. **Ingestion (SQL/Trino):** Dynamically fetches open opportunities based on the current Fiscal Year and targets specific managers.
2. **Processing (Python/Pandas):** The core engine. Applies 7 strict business rules to the dataset using vectorized operations, generates audit logs, and creates a targeted JSON payload.
3. **Orchestration & Delivery (Power Automate):** Intercepts the Python output via email, dynamically routes the data, archives snapshots in SharePoint/OneDrive, and delivers branded HTML emails to stakeholders.

---

## Repository Structure

* `crm_hygiene_engine.ipynb` - The main Python notebook containing the extraction, processing, and payload generation logic.
* `queries/` 
  * `hygiene_base_extraction.sql` - Trino SQL query for base data extraction.
* `schemas/`
  * `power_automate_schema.json` - The exact JSON schema used in Power Automate (includes `["type", "null"]` fail-safes).
* `power_automate/`
  * `images/` - Architecture screenshots and Power Automate flow structure for visual reference.

---

## The 7 Rules of Hygiene

This engine evaluates the pipeline against the following rules:
1. **OL < RTA:** Outlook is below the Renewal Target Amount.
2. **OL < DS:** Outlook is below Downside.
3. **US < OL:** Upside is below Outlook.
4. **Close Date in Past:** The opportunity close date has expired.
5. **Missing OL or US:** Financial fields are empty/zero.
6. **Stagnant Opp:** Opportunity has been in the same stage for >= 30 days.

---

## Setup & Execution

### Prerequisites
* Python 3.8+
* `pandas`, `datetime`, `json`, `os`
* Internal Mail Library (`linkedin.mail.liemail`)
* Access credentials for the Trino database.

### Running the Engine
1. Clone the repository.
2. Open `crm_hygiene_engine.ipynb`.
3. Set `TEST_MODE = False` in Block 1 for production (or `True` to route all emails to yourself).
4. Run all cells. The script handles the rest, triggering the Power Automate flow automatically.

---

## Maintenance & Troubleshooting

**How to add or remove a Manager:**
* Update the SQL CTE in `queries/hygiene_base_extraction.sql` to include/exclude the manager's hierarchy.
* No changes are needed in Power Automate; the flow dynamically loops through whatever managers are present in the JSON payload.

**Power Automate Flow Fails (Validation Error):**
* This usually means the CRM introduced a new null value. Check the `schemas/power_automate_schema.json` in this repo and ensure the failing field is set to accept `["type", "null"]`.

**Disaster Recovery:**
* If the Power Automate flow is accidentally deleted, go to the Power Automate portal -> Import -> Upload the `.zip` file from the `power_automate/` folder to restore it instantly.
