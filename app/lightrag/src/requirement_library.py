from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class RequirementDefinition:
    requirement_id: str
    handbook_section: str
    title: str
    requirement_text: str
    category: str
    severity: str
    trigger_conditions: list[str] = field(default_factory=list)
    expected_evidence_patterns: list[str] = field(default_factory=list)
    suggested_fix_template: str = ""
    retrieval_query: str = ""


INITIAL_REQUIREMENTS: list[RequirementDefinition] = [
    RequirementDefinition(
        requirement_id="rss_5_1_open_recruitment",
        handbook_section="5.1",
        title="open and fair recruitment exercise",
        requirement_text="The consultant should conduct RSS recruitment in an open and fair manner and define recruitment process controls.",
        category="process",
        severity="high",
        trigger_conditions=["recruitment", "recruit", "job offer", "interview"],
        expected_evidence_patterns=[
            "recruitment process",
            "selection criteria",
            "interview",
            "open recruitment",
        ],
        suggested_fix_template="Add explicit recruitment process language covering open and fair recruitment, interview controls, and selection criteria for RSS vacancies.",
        retrieval_query="open and fair recruitment RSS selection criteria interview waiting list",
    ),
    RequirementDefinition(
        requirement_id="rss_5_3_declarations",
        handbook_section="5.3",
        title="declarations and integrity conditions",
        requirement_text="Applicants should provide declarations on convictions or prior RSS termination, and RSS contracts should include integrity-related conditions.",
        category="contract_clause",
        severity="critical",
        trigger_conditions=["employment", "appointment", "declaration", "conviction"],
        expected_evidence_patterns=[
            "declaration",
            "convicted",
            "termination",
            "prevention of bribery",
        ],
        suggested_fix_template="Add declaration and contract provisions for convictions, prior RSS termination, anti-bribery, and integrity obligations.",
        retrieval_query="declaration conviction termination prevention of bribery integrity RSS employment",
    ),
    RequirementDefinition(
        requirement_id="rss_5_5_consent_before_employment",
        handbook_section="5.5",
        title="consent before RSS employment",
        requirement_text="Applicants should consent to the collection and transfer of relevant data before RSS employment is confirmed.",
        category="mandatory",
        severity="critical",
        trigger_conditions=["consent", "employment", "personal data", "rss database"],
        expected_evidence_patterns=[
            "consent",
            "personal data",
            "transfer",
            "government",
        ],
        suggested_fix_template="Add a consent clause covering collection, use, and transfer of applicant and RSS personal data before employment approval.",
        retrieval_query="consent before RSS employment personal data transfer government",
    ),
    RequirementDefinition(
        requirement_id="rss_5_12_outside_work",
        handbook_section="5.12",
        title="outside work approval controls",
        requirement_text="Outside work should require prior written approval and managing department consent where applicable.",
        category="contract_clause",
        severity="high",
        trigger_conditions=["outside work", "approval", "consent", "attendance"],
        expected_evidence_patterns=[
            "outside work",
            "prior written approval",
            "written consent",
            "normal hours",
        ],
        suggested_fix_template="Add outside work restrictions with prior written approval and managing department consent requirements.",
        retrieval_query="outside work prior written approval written consent normal hours",
    ),
    RequirementDefinition(
        requirement_id="rss_6_2_rss_manual",
        handbook_section="6.2",
        title="RSS manual and supervision strategy",
        requirement_text="The consultant should maintain an RSS Manual and site supervision strategy with establishment, duties, attendance, and supervision procedures.",
        category="mandatory",
        severity="critical",
        trigger_conditions=["rss manual", "site supervision", "establishment", "duties"],
        expected_evidence_patterns=[
            "RSS Manual",
            "staff establishment",
            "duties",
            "normal hours of attendance",
        ],
        suggested_fix_template="Add or strengthen the RSS Manual requirement, including establishment, duties, attendance, and supervision procedures.",
        retrieval_query="RSS Manual staff establishment duties hours of attendance supervision procedures",
    ),
    RequirementDefinition(
        requirement_id="rss_6_3_performance_appraisal",
        handbook_section="6.3",
        title="performance appraisal system",
        requirement_text="The consultant should establish a transparent and fair RSS performance appraisal system with reporting intervals and appeal handling.",
        category="process",
        severity="high",
        trigger_conditions=["performance appraisal", "performance report", "appeal"],
        expected_evidence_patterns=[
            "performance appraisal",
            "performance report",
            "appeal",
            "12-month",
        ],
        suggested_fix_template="Add a transparent RSS performance appraisal system, including reporting frequency, interviews, and appeal handling.",
        retrieval_query="RSS performance appraisal performance report appeal 12-month",
    ),
    RequirementDefinition(
        requirement_id="rss_6_5_training",
        handbook_section="6.5",
        title="training arrangements",
        requirement_text="The consultant should arrange required safety and induction training for RSS and maintain training records.",
        category="process",
        severity="medium",
        trigger_conditions=["training", "safety", "induction"],
        expected_evidence_patterns=[
            "training",
            "safety training",
            "induction",
            "training record",
        ],
        suggested_fix_template="Add obligations for safety training, induction training, and maintenance of training records for RSS.",
        retrieval_query="RSS training safety training induction training record",
    ),
    RequirementDefinition(
        requirement_id="rss_7_standard_provisions",
        handbook_section="7.1-7.2",
        title="standard consultancy provisions",
        requirement_text="The tender should align with standard consultancy provisions and the schedule of RSS standards and duties.",
        category="contract_clause",
        severity="high",
        trigger_conditions=["standard provisions", "schedule", "standards and duties"],
        expected_evidence_patterns=[
            "Schedule of Resident Site Staff Standards and Duties",
            "Special Conditions of Employment",
            "standards and duties",
        ],
        suggested_fix_template="Align the tender wording with the standard consultancy provisions and the schedule of RSS standards and duties.",
        retrieval_query="Schedule of Resident Site Staff Standards and Duties Special Conditions of Employment standard provisions",
    ),
]


def list_requirements(requirement_ids: list[str] | None = None) -> list[RequirementDefinition]:
    if not requirement_ids:
        return INITIAL_REQUIREMENTS
    wanted = set(requirement_ids)
    return [item for item in INITIAL_REQUIREMENTS if item.requirement_id in wanted]
