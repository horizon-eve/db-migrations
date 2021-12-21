
const regex = /@\w+@/igm;

function sqlreplace(db, data) {
  let matches = data.match(regex);
  if (matches) {
    matches.forEach(m => {
      let name = m.replace(/@/g, '')
      if (db.internals.argv[name]) {
        data = data.replace(m, db.internals.argv[name])
      } else if (process.env[name]) {
        data = data.replace(m, process.env[name])
      } else if (db.connection[name]) {
        data = data.replace(m, db.connection[name])
      }
    })
  }
  return data
}

module.exports = sqlreplace;
