#include "taichi/util/offline_cache.h"

namespace taichi::lang::offline_cache {

constexpr std::size_t offline_cache_key_length = 65;
constexpr std::size_t min_mangled_name_length = offline_cache_key_length + 2;

void disable_offline_cache_if_needed(CompileConfig *config) {
  TI_ASSERT(config);
  if (config->offline_cache) {
    if (config->print_preprocessed_ir || config->print_ir ||
        config->print_accessor_ir) {
      config->offline_cache = false;
      TI_WARN(
          "Disable offline_cache because print_preprocessed_ir or print_ir or "
          "print_accessor_ir is enabled");
    }
  }
}

std::string get_cache_path_by_arch(const std::string &base_path, Arch arch) {
  std::string subdir;
  if (arch_uses_llvm(arch)) {
    subdir = "llvm";
  } else if (arch == Arch::vulkan || arch == Arch::opengl) {
    subdir = "gfx";
  } else if (arch == Arch::metal) {
    subdir = "metal";
  } else {
    return base_path;
  }
  return taichi::join_path(base_path, subdir);
}

bool enabled_wip_offline_cache(bool enable_hint) {
  // CompileConfig::offline_cache is a global option to enable offline cache on
  // all backends To disable WIP offline cache by default & enable when
  // developing/testing:
  const char *enable_env = std::getenv("TI_WIP_OFFLINE_CACHE");
  return enable_hint && enable_env && std::strncmp("1", enable_env, 1) == 0;
}

std::string mangle_name(const std::string &primal_name,
                        const std::string &key) {
  // Result: {primal_name}{key: char[65]}_{(checksum(primal_name)) ^
  // checksum(key)}
  if (key.size() != offline_cache_key_length) {
    return primal_name;
  }
  std::size_t checksum1{0}, checksum2{0};
  for (auto &e : primal_name) {
    checksum1 += std::size_t(e);
  }
  for (auto &e : key) {
    checksum2 += std::size_t(e);
  }
  return fmt::format("{}{}_{}", primal_name, key, checksum1 ^ checksum2);
}

bool try_demangle_name(const std::string &mangled_name,
                       std::string &primal_name,
                       std::string &key) {
  if (mangled_name.size() < min_mangled_name_length) {
    return false;
  }

  std::size_t checksum{0}, checksum1{0}, checksum2{0};
  auto pos = mangled_name.find_last_of('_');
  if (pos == std::string::npos) {
    return false;
  }
  try {
    checksum = std::stoull(mangled_name.substr(pos + 1));
  } catch (const std::exception &) {
    return false;
  }

  std::size_t i = 0, primal_len = pos - offline_cache_key_length;
  for (i = 0; i < primal_len; ++i) {
    checksum1 += (int)mangled_name[i];
  }
  for (; i < pos; ++i) {
    checksum2 += (int)mangled_name[i];
  }
  if ((checksum1 ^ checksum2) != checksum) {
    return false;
  }

  primal_name = mangled_name.substr(0, primal_len);
  key = mangled_name.substr(primal_len, offline_cache_key_length);
  TI_ASSERT(key.size() == offline_cache_key_length);
  TI_ASSERT(primal_name.size() + key.size() == pos);
  return true;
}

}  // namespace taichi::lang::offline_cache
