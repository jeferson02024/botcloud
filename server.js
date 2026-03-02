
const express = require('express');
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcrypt');
const session = require('express-session');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use(session({
    secret: 'ULTRA_SECRET_KEY_2026',
    resave: false,
    saveUninitialized: false,
    cookie: { secure: false }
}));

app.use(express.static(__dirname));

const USERS_FILE = path.join(__dirname, 'users.json');

function readUsers() {
    if (!fs.existsSync(USERS_FILE)) return [];
    return JSON.parse(fs.readFileSync(USERS_FILE));
}

function saveUsers(users) {
    fs.writeFileSync(USERS_FILE, JSON.stringify(users, null, 2));
}

// ADMIN
const ADMIN_EMAIL = "jefersonrotello@gmail.com";
const ADMIN_PASS_HASH = bcrypt.hashSync("28072010j", 10);

// REGISTER
app.post('/api/register', async (req, res) => {
    const { email, password } = req.body;
    if (!email || !password) return res.json({ error: "Preencha todos os campos" });

    let users = readUsers();
    if (users.find(u => u.email === email)) {
        return res.json({ error: "Usuário já existe" });
    }

    const hashed = await bcrypt.hash(password, 10);

    users.push({
        email,
        password: hashed,
        plan: "BASICO",
        createdAt: new Date()
    });

    saveUsers(users);
    res.json({ success: true });
});

// LOGIN
app.post('/api/login', async (req, res) => {
    const { email, password } = req.body;

    // ADMIN LOGIN
    if (email === ADMIN_EMAIL && await bcrypt.compare(password, ADMIN_PASS_HASH)) {
        req.session.admin = true;
        return res.json({ admin: true });
    }

    let users = readUsers();
    const user = users.find(u => u.email === email);
    if (!user) return res.json({ error: "Credenciais inválidas" });

    const valid = await bcrypt.compare(password, user.password);
    if (!valid) return res.json({ error: "Credenciais inválidas" });

    req.session.user = user.email;
    res.json({ success: true });
});

// UPGRADE PLAN (Admin only simulation)
app.post('/api/upgrade', (req, res) => {
    if (!req.session.admin) return res.json({ error: "Acesso negado" });

    const { email, plan } = req.body;
    let users = readUsers();
    const user = users.find(u => u.email === email);
    if (!user) return res.json({ error: "Usuário não encontrado" });

    user.plan = plan;
    saveUsers(users);

    res.json({ success: true });
});

function requireUser(req, res, next) {
    if (!req.session.user) return res.redirect('/login.html');
    next();
}

function requireAdmin(req, res, next) {
    if (!req.session.admin) return res.redirect('/login.html');
    next();
}

app.get('/dashboard', requireUser, (req, res) => {
    res.sendFile(path.join(__dirname, 'dashboard.html'));
});

app.get('/admin', requireAdmin, (req, res) => {
    res.sendFile(path.join(__dirname, 'admin.html'));
});

app.listen(PORT, () => {
    console.log("🚀 BotCloud PRO rodando na porta " + PORT);
});
