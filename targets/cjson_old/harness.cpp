#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>

#include "cJSON.h"

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
  if (!p) {
    return;
  }

  std::memset(p, 'A', 8);
  std::free(p);

  volatile char* vp = p;
  *vp = 'X';
}

static void exercise_string_fields(cJSON* node) {
  if (!node) {
    return;
  }

  if (cJSON_IsString(node) && node->valuestring) {
    volatile size_t len = std::strlen(node->valuestring);
    (void)len;
  }

  if (node->string) {
    volatile size_t key_len = std::strlen(node->string);
    (void)key_len;
  }
}

static void exercise_number_fields(cJSON* node) {
  if (!node) {
    return;
  }

  if (cJSON_IsNumber(node)) {
    volatile double d = node->valuedouble;
    volatile int i = node->valueint;
    (void)d;
    (void)i;
  }
}

static void exercise_array(cJSON* node, int depth, int max_depth, int budget);
static void exercise_object(cJSON* node, int depth, int max_depth, int budget);

static void exercise_node(cJSON* node, int depth = 0, int max_depth = 5, int budget = 128) {
  if (!node || depth > max_depth || budget <= 0) {
    return;
  }

  int visited = 0;
  cJSON* cur = node;

  while (cur && visited < budget) {
    exercise_string_fields(cur);
    exercise_number_fields(cur);

    if (cJSON_IsArray(cur)) {
      exercise_array(cur, depth + 1, max_depth, budget - visited - 1);
    } else if (cJSON_IsObject(cur)) {
      exercise_object(cur, depth + 1, max_depth, budget - visited - 1);
    } else if (cur->child) {
      exercise_node(cur->child, depth + 1, max_depth, budget - visited - 1);
    }

    cur = cur->next;
    ++visited;
  }
}

static void exercise_array(cJSON* node, int depth, int max_depth, int budget) {
  if (!node || budget <= 0) {
    return;
  }

  int size = cJSON_GetArraySize(node);
  volatile int vsz = size;
  (void)vsz;

  if (size > 0) {
    cJSON* first = cJSON_GetArrayItem(node, 0);
    if (first) {
      exercise_node(first, depth, max_depth, budget - 1);
    }

    cJSON* last = cJSON_GetArrayItem(node, size - 1);
    if (last && last != first) {
      exercise_node(last, depth, max_depth, budget - 2);
    }
  }
}

static void exercise_object(cJSON* node, int depth, int max_depth, int budget) {
  if (!node || budget <= 0) {
    return;
  }

  const char* interesting_keys[] = {
      "id", "name", "type", "value", "items", "data", "meta", "user", "admin"
  };

  for (size_t i = 0; i < sizeof(interesting_keys) / sizeof(interesting_keys[0]); ++i) {
    cJSON* item = cJSON_GetObjectItemCaseSensitive(node, interesting_keys[i]);
    if (item) {
      exercise_node(item, depth, max_depth, budget - static_cast<int>(i) - 1);
    }
  }

  if (node->child) {
    exercise_node(node->child, depth, max_depth, budget - 1);
  }
}

static void exercise_roundtrip(cJSON* root) {
  if (!root) {
    return;
  }

  char* compact = cJSON_PrintUnformatted(root);
  if (compact) {
    cJSON* reparsed = cJSON_Parse(compact);
    if (reparsed) {
      exercise_node(reparsed);
      cJSON_Delete(reparsed);
    }
    std::free(compact);
  }

  char* pretty = cJSON_Print(root);
  if (pretty) {
    cJSON* reparsed2 = cJSON_Parse(pretty);
    if (reparsed2) {
      exercise_node(reparsed2);
      cJSON_Delete(reparsed2);
    }
    std::free(pretty);
  }
}

static void exercise_duplicate(cJSON* root) {
  if (!root) {
    return;
  }

  cJSON* dup1 = cJSON_Duplicate(root, 0);
  if (dup1) {
    cJSON_Delete(dup1);
  }

  cJSON* dup2 = cJSON_Duplicate(root, 1);
  if (dup2) {
    exercise_node(dup2);
    cJSON_Delete(dup2);
  }
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size > 65536) {
    return 0;
  }

  char* buf = static_cast<char*>(std::malloc(size + 1));
  if (!buf) {
    return 0;
  }

  if (size > 0) {
    std::memcpy(buf, data, size);
  }
  buf[size] = '\0';

  if (env_enabled("FUZZPIPE_DEMO_CRASH") && contains_demo_trigger(buf)) {
    trigger_demo_asan_use_after_free();
    std::free(buf);
    return 0;
  }

  cJSON* root = cJSON_Parse(buf);
  if (root) {
    exercise_node(root);
    exercise_roundtrip(root);
    exercise_duplicate(root);
    cJSON_Delete(root);
  }

  std::free(buf);
  return 0;
}