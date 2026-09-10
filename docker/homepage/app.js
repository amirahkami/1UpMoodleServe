const host = window.location.hostname;

document.getElementById("moodle-link").href = `https://moodle.${host}`;
document.getElementById("account-link").href = `https://iam.${host}`;
