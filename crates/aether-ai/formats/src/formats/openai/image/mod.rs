use base64::Engine as _;
use url::Url;

pub mod request;
pub mod spec;
pub mod stream;

pub(crate) const MAX_OPENAI_IMAGE_DATA_BYTES: usize = 64 * 1024 * 1024;
pub(crate) const MAX_OPENAI_IMAGE_EXTERNAL_URL_BYTES: usize = 64 * 1024;
pub(crate) const MAX_OPENAI_IMAGE_REVISED_PROMPT_BYTES: usize = 256 * 1024;

pub(crate) fn is_safe_openai_image_base64_payload(value: &str) -> bool {
    if value.is_empty()
        || value.len() > MAX_OPENAI_IMAGE_DATA_BYTES
        || value.len() % 4 == 1
        || value
            .bytes()
            .any(|byte| byte.is_ascii_whitespace() || byte.is_ascii_control())
    {
        return false;
    }
    let bytes = value.as_bytes();
    let first_padding = bytes.iter().position(|byte| *byte == b'=');
    if let Some(index) = first_padding {
        let padding = bytes.len() - index;
        if padding > 2
            || bytes[index..].iter().any(|byte| *byte != b'=')
            || !bytes.len().is_multiple_of(4)
        {
            return false;
        }
    }
    bytes[..first_padding.unwrap_or(bytes.len())]
        .iter()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(*byte, b'+' | b'/'))
}

/// Detects the image format from a bounded prefix of a base64 payload.
///
/// Provider fields can be absent or stale, so response discovery uses the
/// bytes themselves when they carry a recognizable signature. Only a short
/// prefix is decoded; full image decoding remains outside the gateway path.
pub fn openai_image_payload_format_from_base64(value: &str) -> Option<&'static str> {
    let value = value.trim();
    if !is_safe_openai_image_base64_payload(value) {
        return None;
    }
    let prefix_len = value.len().min(8 * 1024);
    let prefix_len = prefix_len - (prefix_len % 4);
    let prefix = &value.as_bytes()[..prefix_len];
    let decoded = base64::engine::general_purpose::STANDARD
        .decode(prefix)
        .or_else(|_| base64::engine::general_purpose::STANDARD_NO_PAD.decode(prefix))
        .ok()?;
    openai_image_payload_format(&decoded)
}

pub fn openai_image_payload_format(value: &[u8]) -> Option<&'static str> {
    if value.len() >= 24 && value.starts_with(b"\x89PNG\r\n\x1a\n") && &value[12..16] == b"IHDR" {
        return Some("png");
    }
    if value.len() >= 3 && value.starts_with(&[0xff, 0xd8, 0xff]) {
        return Some("jpeg");
    }
    if value.len() >= 12 && &value[..4] == b"RIFF" && &value[8..12] == b"WEBP" {
        return Some("webp");
    }
    if value.len() >= 6 && (&value[..6] == b"GIF87a" || &value[..6] == b"GIF89a") {
        return Some("gif");
    }
    let text = value.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(value);
    let text = text
        .iter()
        .position(|byte| !byte.is_ascii_whitespace())
        .map(|start| &text[start..])
        .unwrap_or_default();
    if text
        .windows(4)
        .any(|window| window.eq_ignore_ascii_case(b"<svg"))
    {
        return Some("svg");
    }
    None
}

pub(crate) fn normalize_openai_image_output_format(value: &str) -> Option<&'static str> {
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

pub(crate) fn openai_image_output_format_mime_type(value: &str) -> Option<&'static str> {
    match normalize_openai_image_output_format(value)? {
        "png" => Some("image/png"),
        "jpeg" => Some("image/jpeg"),
        "webp" => Some("image/webp"),
        "svg" => Some("image/svg+xml"),
        "gif" => Some("image/gif"),
        _ => None,
    }
}

pub(crate) fn bounded_openai_image_revised_prompt(value: &str) -> Option<&str> {
    let value = value.trim();
    (!value.is_empty() && value.len() <= MAX_OPENAI_IMAGE_REVISED_PROMPT_BYTES).then_some(value)
}

pub(crate) fn parse_safe_openai_image_data_url(value: &str) -> Option<(&'static str, &str)> {
    let (metadata, payload) = value.trim().split_once(',')?;
    let mime_type = metadata.strip_prefix("data:")?.strip_suffix(";base64")?;
    let mime_type = safe_openai_image_mime_type(mime_type.trim())?;
    (!payload.is_empty() && is_safe_openai_image_base64_payload(payload))
        .then_some((mime_type, payload))
}

pub(crate) fn safe_openai_image_mime_type(value: &str) -> Option<&'static str> {
    if value.eq_ignore_ascii_case("image/png") {
        Some("image/png")
    } else if value.eq_ignore_ascii_case("image/jpeg") || value.eq_ignore_ascii_case("image/jpg") {
        Some("image/jpeg")
    } else if value.eq_ignore_ascii_case("image/webp") {
        Some("image/webp")
    } else {
        None
    }
}

pub(crate) fn sanitize_openai_image_source_url(value: &str) -> Option<String> {
    let value = value.trim();
    if value.is_empty()
        || value
            .chars()
            .any(|character| character.is_ascii_control() || character.is_whitespace())
    {
        return None;
    }
    if let Some((mime_type, payload)) = parse_safe_openai_image_data_url(value) {
        return Some(format!("data:{mime_type};base64,{payload}"));
    }
    if value.len() > MAX_OPENAI_IMAGE_EXTERNAL_URL_BYTES {
        return None;
    }
    let parsed = Url::parse(value).ok()?;
    if !matches!(parsed.scheme(), "http" | "https")
        || parsed.host_str().is_none()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
    {
        return None;
    }
    Some(value.to_string())
}
