
mailer_manual_authorize :: (client_id: string, client_secret: string) {
    // direct_redirect_uri :: "urn:ietf:wg:oauth:2.0:oob";
    direct_redirect_uri :: "http://127.0.0.1:8080";
    auth_base_url :: "https://accounts.google.com/o/oauth2/v2/auth";
    scope :: "https://www.googleapis.com/auth/gmail.send";

    encode_parts := [2] string.[
        .["client_id", client_id],
        .["redirect_uri", direct_redirect_uri],
        .["scope", scope],
        .["response_type", "code"],
        .["access_type", "offline"],
    ];
    
    authorize_url := tprint("%?%", auth_base_url, url_encode(..encode_parts,, temp));
    
    print("Go to %\n", authorize_url);
}

mailer_authorize :: (client_id: string, client_secret: string, refresh_token: string) -> bool {
    free(mailer_client_id);
    mailer_client_id = copy_string(client_id);
    free(mailer_client_secret);
    mailer_client_secret = copy_string(client_secret);
    free(mailer_refresh_token);
    mailer_refresh_token = copy_string(refresh_token);

    return mailer_maybe_authorize();
}

format_html_email :: (from_email: string, from_name: string, to_email: string, subject: string, header: string, body: string) -> string {
EMAIL :: #string EMAIL
To: %
From: "%" <%>
Subject: %
MIME-Version: 1.0
Content-Type: text/html; charset="UTF-8"

<html>
    <body>
        <h1>%</h1>
%
    </body>
</html>
EMAIL

    body_builder: String_Builder;
    body_parts := split(body, "\n");
    defer array_free(body_parts);

    for body_part: body_parts {
        append(*body_builder, "        <p>");
        append(*body_builder, body_part);
        append(*body_builder, "</p>\n");
    }

    formatted_body := builder_to_string(*body_builder);
    defer free(formatted_body);

    return sprint(EMAIL, to_email, from_name, from_email, subject, header, formatted_body);
}

mailer_send :: (email: string) -> bool {
    endpoint :: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send";

    if !mailer_maybe_authorize() {
        return false;
    }

    access_header := tprint("Authorization: Bearer %\0", mailer_access_token);

    content_replaced := base64_encode(email);
    defer free(content_replaced);

    json :: "{\"raw\": \"%\"}";
    json_message := sprint(json, content_replaced);
    defer free(json_message);

    success, response := curl_request_post_json_with_headers(endpoint, access_header.data, json_message);
    print("Sent: % %\n", success, response);

    return success;
}

url_encode :: (parts: .. [2] string) -> string {
    curl := curl_easy_init();
    defer curl_easy_cleanup(curl);

    builder: String_Builder;
    for part, index: parts {
        append(*builder, part[0]);
        append(*builder, "=");

        encoded := curl_easy_escape(curl, part[1].data, xx part[1].count);
        defer curl_free(encoded);

        append(*builder, to_string(encoded));

        if index < parts.count - 1 {
            append(*builder, "&");
        }
    }

    return builder_to_string(*builder);
}

#scope_file

mailer_client_id: string;
mailer_client_secret: string;
mailer_refresh_token: string;

mailer_access_token: string;
mailer_access_expiration: float64;

mailer_maybe_authorize :: () -> bool {
    if !mailer_client_id || !mailer_client_secret || !mailer_refresh_token {
        print("You must authorize the mailer.\n");
        return true;
    }

    if mailer_access_token && seconds_since_init() < mailer_access_expiration - 60 {
        return true;
    }

    access_token_success, access_token_response := curl_request_post("https://oauth2.googleapis.com/token", "client_id", mailer_client_id, "client_secret", mailer_client_secret, "refresh_token", mailer_refresh_token, "grant_type", "refresh_token");
    if !access_token_success {
        print("Could not authorize mailer. %\n", access_token_response);
        return false;
    }

    AuthorizeResponse :: struct {
        expires_in: int;
        access_token: string;
    }
    response, memory := json_parse(access_token_response, AuthorizeResponse);
    defer free(memory);

    free(mailer_access_token);
    mailer_access_token = copy_string(response.access_token);
    mailer_access_expiration = seconds_since_init() + response.expires_in;

    return true;
}

// json_replace :: (line: string) -> string {
//     replaced_1 := replace(line, "\"", "\\\"");
//     defer free(replaced_1);

//     return replace(replaced_1, "\n", "\\n");
// }

curl_request_post :: (url: *u8, key_values: ..string) -> bool, string {
    assert(key_values.count % 2 == 0, "Must provide an even number of key values for a post request. %\n", key_values);

    curl := curl_easy_init();
    defer curl_easy_cleanup(curl);
    assert(!!curl, "Curl could not be initialized.");

    mime := curl_mime_init(curl);
    defer curl_mime_free(mime);

    curl_easy_setopt(curl, .MIMEPOST, mime);
    curl_easy_setopt(curl, .URL, url);

    i := 0;
    while i < key_values.count {
        defer i += 2;

        key := key_values[i];
        value := key_values[i + 1];

        c_key := alloc_string(key.count + 1);
        defer free(c_key);
        memcpy(c_key.data, key.data, key.count);
        c_key[c_key.count - 1] = 0;

        part := curl_mime_addpart(mime);
        curl_mime_name(part, c_key.data);
        curl_mime_data(part, value.data, cast(u64) value.count);
    }

    builder: String_Builder;
    curl_easy_setopt(curl, .WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, .WRITEDATA, *builder);

    success := curl_easy_perform(curl) == 0;
    return success, builder_to_string(*builder);
}

curl_request_post_json_with_headers :: (url: *u8, header: *u8, json: string) -> bool, string {
    curl := curl_easy_init();
    defer curl_easy_cleanup(curl);
    assert(!!curl, "Curl could not be initialized.");
    
    list: *curl_slist;
    defer curl_slist_free_all(list);
    list = curl_slist_append(list, header);
    list = curl_slist_append(list, "Content-Type: application/json");
    curl_easy_setopt(curl, .HTTPHEADER, list);

    null_termined_json := alloc_string(json.count + 1);
    defer free(null_termined_json);
    memcpy(null_termined_json.data, json.data, json.count);
    null_termined_json[null_termined_json.count - 1] = #char "\0";

    curl_easy_setopt(curl, .POSTFIELDS, null_termined_json.data);
    curl_easy_setopt(curl, .URL, url);

    output_builder: String_Builder;
    curl_easy_setopt(curl, .WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, .WRITEDATA, *output_builder);

    result := curl_easy_perform(curl);
    return result == 0, builder_to_string(*output_builder);
}

write_callback :: (contents: *u8, count: u64, size: u64, builder: *String_Builder) -> u64 #c_call {
    total_size := count * size;
    new_context: Context;
    push_context new_context {
        // Append to the builder
        append(builder, contents, cast(s64) total_size);
    }
    return total_size;
}

#import "Basic";
#import "Curl";
#import "Base64";
#import "String";

#import "ContiguousJsonJai";
