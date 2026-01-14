#!/usr/bin/env bun

import { parse } from "yaml";
import { $ } from "bun";
import { join } from "path";

interface Rule {
  domains?: string;
  subnets?: string;
  list?: string[];
  outbound: string;
}

interface Config {
  rules: Rule[];
}

interface OutboundData {
  domains: string[];
  subnets: string[];
}

const normalizeDomainSuffix = (value: string): string => {
  let v = value.trim().toLowerCase();
  if (v.startsWith("*.")) v = v.slice(2);
  if (v.startsWith(".")) v = v.slice(1);
  return v;
};

const isIPv4 = (value: string): boolean => {
  const parts = value.split(".");
  if (parts.length !== 4) return false;
  return parts.every((p) => {
    if (!/^\d+$/.test(p)) return false;
    const n = Number(p);
    return n >= 0 && n <= 255;
  });
};

const isIPv6 = (value: string): boolean => {
  // Lightweight check: avoid over-validating, just ensure it's plausible.
  return value.includes(":") && /^[0-9a-fA-F:]+$/.test(value);
};

const normalizeCidr = (value: string): string => {
  const v = value.trim();
  if (v.includes("/")) return v;
  if (isIPv4(v)) return `${v}/32`;
  if (isIPv6(v)) return `${v}/128`;
  return v;
};

const isIpOrCidr = (value: string): boolean => {
  const v = value.trim();
  const [ip, prefix] = v.split("/", 2);
  if (!ip) return false;
  if (prefix !== undefined && prefix !== "" && !/^\d+$/.test(prefix)) return false;

  if (isIPv4(ip)) {
    if (prefix === undefined) return true;
    const p = Number(prefix);
    return p >= 0 && p <= 32;
  }

  if (isIPv6(ip)) {
    if (prefix === undefined) return true;
    const p = Number(prefix);
    return p >= 0 && p <= 128;
  }

  return false;
};

const addMixedEntry = (value: string, data: OutboundData) => {
  const v = value.trim();
  if (!v) return;

  if (isIpOrCidr(v)) {
    data.subnets.push(normalizeCidr(v));
    return;
  }

  // Domain is always suffix (no wildcards).
  data.domains.push(normalizeDomainSuffix(v));
};

const readLines = async (source: string, baseDir: string): Promise<string[]> => {
  let content: string;

  if (source.startsWith("http://") || source.startsWith("https://")) {
    console.log(`  Fetching: ${source}`);
    const response = await fetch(source);
    if (!response.ok) {
      throw new Error(`Failed to fetch ${source}: ${response.statusText}`);
    }
    content = await response.text();
  } else {
    const filePath = join(baseDir, source);
    console.log(`  Reading: ${filePath}`);
    const file = Bun.file(filePath);
    content = await file.text();
  }

  return content
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"));
};

const generateSrs = async (
  outboundName: string,
  data: OutboundData,
  outputDir: string
): Promise<void> => {
  const jsonDir = join(outputDir, "json");
  const srsDir = join(outputDir, "srs");

  await Bun.write(join(jsonDir, ".gitkeep"), "");
  await Bun.write(join(srsDir, ".gitkeep"), "");

  const rules: Record<string, string[]>[] = [];

  if (data.domains.length > 0) {
    rules.push({ domain_suffix: data.domains });
  }

  if (data.subnets.length > 0) {
    rules.push({ ip_cidr: data.subnets });
  }

  if (rules.length === 0) {
    console.log(`  Skipping ${outboundName}: no rules`);
    return;
  }

  const ruleSet = {
    version: 3,
    rules,
  };

  const jsonPath = join(jsonDir, `${outboundName}-rule.json`);
  const srsPath = join(srsDir, `${outboundName}-rule.srs`);

  await Bun.write(jsonPath, JSON.stringify(ruleSet, null, 2));
  console.log(`  Generated JSON: ${jsonPath}`);

  try {
    await $`sing-box rule-set compile ${jsonPath} -o ${srsPath}`.quiet();
    console.log(`  Compiled SRS: ${srsPath}`);
  } catch (error) {
    console.error(`  Failed to compile ${jsonPath}:`, error);
  }
};

const main = async () => {
  const configPath = join(import.meta.dir, "config.yaml");
  const outputDir = import.meta.dir;

  console.log("Reading config:", configPath);
  const configFile = Bun.file(configPath);
  const configContent = await configFile.text();
  const config = parse(configContent) as Config;

  const outbounds = new Map<string, OutboundData>();

  for (const rule of config.rules) {
    if (!outbounds.has(rule.outbound)) {
      outbounds.set(rule.outbound, { domains: [], subnets: [] });
    }

    const data = outbounds.get(rule.outbound)!;

    if (rule.domains) {
      const domains = await readLines(rule.domains, import.meta.dir);
      data.domains.push(...domains.map(normalizeDomainSuffix));
    }

    if (rule.subnets) {
      const subnets = await readLines(rule.subnets, import.meta.dir);
      data.subnets.push(...subnets.map(normalizeCidr));
    }

    if (rule.list && rule.list.length > 0) {
      for (const entry of rule.list) {
        const v = String(entry ?? "").trim();
        if (!v) continue;

        // If it's clearly an IP/CIDR, treat it as subnet.
        if (isIpOrCidr(v)) {
          data.subnets.push(normalizeCidr(v));
          continue;
        }

        // Allow including file paths / URLs that contain mixed entries.
        if (v.startsWith("http://") || v.startsWith("https://") || v.includes("/")) {
          const lines = await readLines(v, import.meta.dir);
          for (const line of lines) addMixedEntry(line, data);
          continue;
        }

        // Otherwise it's a domain suffix.
        data.domains.push(normalizeDomainSuffix(v));
      }
    }
  }

  console.log("\nGenerating rule sets...");
  for (const [outbound, data] of outbounds) {
    console.log(`\nOutbound: ${outbound}`);
    console.log(`  Domains: ${data.domains.length}, Subnets: ${data.subnets.length}`);

    // Deduplicate
    data.domains = [...new Set(data.domains)];
    data.subnets = [...new Set(data.subnets)];

    await generateSrs(outbound, data, outputDir);
  }

  console.log("\nDone!");
};

main().catch(console.error);
