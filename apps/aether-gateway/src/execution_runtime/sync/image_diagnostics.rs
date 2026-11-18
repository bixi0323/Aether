use serde_json::Value;

use crate::ai_serving::openai_image_payload_format_from_base64;

pub(super) fn attach_openai_image_response_format_diagnostics(
    report_context: &mut Option<Value>,
    response_body: Option<&Value>,
) {
    let Some(context) = report_context.as_mut().and_then(Value::as_object_mut) else {
        return;
    };
    if !context.contains_key("image_request") {
        return;
    }

    let provider_response_output_format = response_body
        .and_then(|body| body.get("output_format"))
        .and_then(Value::as_str)
        .and_then(known_image_output_format);
    let provider_response_payload_format = response_body
        .and_then(|body| body.get("data"))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .find_map(|item| {
            item.get("b64_json")
                .and_then(Value::as_str)
                .and_then(openai_image_payload_format_from_base64)
        });

    let mut diagnostics = context
        .get("image_format_diagnostics")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    if let Some(value) = provider_response_output_format {
        diagnostics.insert("provider_response_output_format".to_string(), value.into());
    }
    if let Some(value) = provider_response_payload_format {
        diagnostics.insert("provider_response_payload_format".to_string(), value.into());
    }
    if !diagnostics.is_empty() {
        context.insert(
            "image_format_diagnostics".to_string(),
            Value::Object(diagnostics),
        );
    }
}

fn known_image_output_format(value: &str) -> Option<&'static str> {
    let value = value.trim();
    if value.eq_ignore_ascii_case("png") {
        Some("png")
    } else if value.eq_ignore_ascii_case("jpeg") || value.eq_ignore_ascii_case("jpg") {
        Some("jpeg")
    } else if value.eq_ignore_ascii_case("webp") {
        Some("webp")
    } else if value.eq_ignore_ascii_case("svg") {
        Some("svg")
    } else if value.eq_ignore_ascii_case("gif") {
        Some("gif")
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use base64::Engine as _;
    use serde_json::json;

    use super::attach_openai_image_response_format_diagnostics;

    #[test]
    fn records_declared_and_actual_response_formats() {
        let mut context = Some(json!({
            "image_request": {"provider_request_output_format": "svg"},
            "image_format_diagnostics": {"provider_request_output_format": "svg"}
        }));
        let payload = base64::engine::general_purpose::STANDARD
            .encode(b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\0\0\0\0\0\0\0");
        attach_openai_image_response_format_diagnostics(
            &mut context,
            Some(&json!({
                "output_format": "svg",
                "data": [{"b64_json": payload}]
            })),
        );

        assert_eq!(
            context.as_ref().unwrap()["image_format_diagnostics"],
            json!({
                "provider_request_output_format": "svg",
                "provider_response_output_format": "svg",
                "provider_response_payload_format": "png"
            })
        );
    }

    #[test]
    fn ignores_non_image_report_contexts() {
        let mut context = Some(json!({"model": "gpt-5"}));
        attach_openai_image_response_format_diagnostics(
            &mut context,
            Some(&json!({"output_format": "png"})),
        );

        assert_eq!(context, Some(json!({"model": "gpt-5"})));
    }
}
