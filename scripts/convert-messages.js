#!/usr/bin/env node

import fs from 'fs';
import path from 'path';

/**
 * Flatten nested JSON object into dot-notation keys
 */
function flattenObject(obj, prefix = '') {
  const flattened = {};
  
  for (const [key, value] of Object.entries(obj)) {
    const newKey = prefix ? `${prefix}.${key}` : key;
    
    if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
      Object.assign(flattened, flattenObject(value, newKey));
    } else if (typeof value === 'string') {
      flattened[newKey] = value;
    }
  }
  
  return flattened;
}

/**
 * Convert JSON messages to PO format
 */
function jsonToPo(jsonMessages, locale) {
  const flattened = flattenObject(jsonMessages);
  
  let po = `msgid ""
msgstr ""
"POT-Creation-Date: ${new Date().toISOString().slice(0, 19)}+0000\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=utf-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"X-Generator: @lingui/cli\\n"
"Language: ${locale}\\n"

`;

  for (const [msgid, msgstr] of Object.entries(flattened)) {
    // Skip schema entries
    if (msgid.startsWith('$')) continue;
    
    // Escape quotes and newlines in the message
    const escapedMsgstr = msgstr
      .replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"')
      .replace(/\n/g, '\\n');
    
    po += `msgid "${msgid}"
msgstr "${escapedMsgstr}"

`;
  }
  
  return po;
}

/**
 * Convert all locale files
 */
async function convertAllLocales() {
  const locales = ['en', 'zh-HK', 'zh-CN', 'zh-TW'];
  
  for (const locale of locales) {
    try {
      const jsonPath = `messages/${locale}.json`;
      const poPath = `src/locales/${locale}/messages.po`;
      
      console.log(`Converting ${jsonPath} to ${poPath}...`);
      
      // Read JSON file
      const jsonContent = fs.readFileSync(jsonPath, 'utf8');
      const jsonMessages = JSON.parse(jsonContent);
      
      // Convert to PO format
      const poContent = jsonToPo(jsonMessages, locale);
      
      // Write PO file
      fs.writeFileSync(poPath, poContent, 'utf8');
      
      console.log(`✓ Converted ${locale}`);
    } catch (error) {
      console.error(`✗ Failed to convert ${locale}:`, error.message);
    }
  }
}

// Run the conversion
convertAllLocales().then(() => {
  console.log('\nConversion complete! Run "bun run i18n:compile" to compile the catalogs.');
}).catch(console.error);
