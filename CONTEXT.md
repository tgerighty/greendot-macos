# Status Monitoring

greendot monitors software status pages so a person can see their current condition from the macOS menu bar.

## Language

**Watched Page**:
A software status page that a person has added to greendot for monitoring.

**Snapshot**:
The most recently observed condition of a Watched Page, including its Severity, Status Page Components, and active Incidents.

**Severity**:
The canonical condition of a Snapshot or Status Page Component: green is operational, yellow is degraded or under maintenance, red is a major outage, and grey is unreachable.

**Status Page Component**:
A named part of a system reported by a Watched Page. It can contain nested Status Page Components.

**Incident**:
An active issue published by a Watched Page.

**Toast**:
A macOS notification created when the displayed Severity of a Watched Page changes and notifications are enabled for that page.
