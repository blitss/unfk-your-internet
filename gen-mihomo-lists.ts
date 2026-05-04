#!/usr/bin/env bun

import { readdirSync } from "node:fs"

const SRC = "sing-box/lists"
const DST = "mihomo/lists"

const transform = (text: string) =>
  text
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => `+.${l}`)
    .join("\n") + "\n"

for (const file of readdirSync(SRC)) {
  if (!file.endsWith(".txt")) continue
  const src = await Bun.file(`${SRC}/${file}`).text()
  await Bun.write(`${DST}/${file}`, transform(src))
  console.log(`${SRC}/${file} -> ${DST}/${file}`)
}

export {}
