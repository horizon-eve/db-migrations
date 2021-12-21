/**
 * Generates reverse drop script from create pg sql
 * USAGE
 * node js/crease2dropsql.js <create.sql>
 *
 */
const fs = require('fs')


let out = []
const f = fs.readFileSync(process.argv[2])
f.toString()
  .replace(/--.*/g, '')
  .replace(/\r?\n/g, '')
  .split(/;+/).forEach(st => {

  if (/^\s*create\b/i.test(st)) {
    let what, name, ext = ''
    let tks = st.toUpperCase().split(/[\s\(\)]+/)
    if (tks[1] === 'OR') {
      what = tks[3]
      name = tks[4]
    } else {
      what = tks[1]
      if (what === 'SCHEMA' && tks[2] === 'AUTHORIZATION') {
        name = tks[3]
      } else {
        name = tks[2]
      }
    }
    if (what === 'TRIGGER' || what === 'POLICY') {
      ext = ' ON ' + tks[tks.findIndex(t => t === 'ON') + 1]
    }
    else if (what === 'SCHEMA') {
      ext = ' CASCADE'
    }
    out.push(`DROP ${what} ${name}${ext};`)

    if (what === 'ROLE' || what === 'USER') {
      out.push(`DROP OWNED BY ${name};`)
    }
  }
})

console.log(out.reverse().join('\n'))
