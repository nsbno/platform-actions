### Terraform Plan {{ ":rocket:" if status === "success" else ":cry:" }}

{{ actor }} planned `{{ ref }}` to the **{{ environment }}** environment. This plan was a {{ status }} {{":rocket:" if status === "success" else ":cry:" }}.

{% if noop %}This was a noop deployment.{% endif %}
