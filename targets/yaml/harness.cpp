#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>

#include <yaml.h>

static bool env_enabled(const char* name) {
    const char* v = std::getenv(name);
    return v &&
           (std::strcmp(v, "1") == 0 ||
            std::strcmp(v, "true") == 0 ||
            std::strcmp(v, "TRUE") == 0);
}

static bool contains_demo_trigger(const char* buf) {
    return std::strstr(buf, "CRASHME") != nullptr;
}

static void trigger_demo_asan_use_after_free() {
    char* p = static_cast<char*>(std::malloc(8));
    if (!p) return;

    std::memset(p, 'A', 8);
    std::free(p);

    volatile char* vp = p;
    *vp = 'X';
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {

    if (size == 0 || size > 65536)
        return 0;

    char* buf = static_cast<char*>(std::malloc(size + 1));
    if (!buf)
        return 0;

    std::memcpy(buf, data, size);
    buf[size] = '\0';

    if (env_enabled("FUZZPIPE_DEMO_CRASH") && contains_demo_trigger(buf)) {
        trigger_demo_asan_use_after_free();
        std::free(buf);
        return 0;
    }

    yaml_parser_t parser;
    yaml_event_t event;

    if (!yaml_parser_initialize(&parser)) {
        std::free(buf);
        return 0;
    }

    yaml_parser_set_input_string(
        &parser,
        reinterpret_cast<const unsigned char*>(buf),
        size
    );

    bool done = false;

    while (!done) {

        if (!yaml_parser_parse(&parser, &event)) {
            break;
        }

        switch (event.type) {
            case YAML_STREAM_END_EVENT:
                done = true;
                break;
            default:
                break;
        }

        yaml_event_delete(&event);
    }

    yaml_parser_delete(&parser);

    std::free(buf);
    return 0;
}
