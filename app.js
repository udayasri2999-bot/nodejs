const express = require('express');
const mysql = require('mysql');
const bcrypt = require('bcryptjs');
const bodyParser = require('body-parser');
const session = require('express-session');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const promClient = require('prom-client');

const app = express();
const port = 9000;

// Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestCounter = new promClient.Counter({
    name: 'http_requests_total',
    help: 'Total HTTP requests',
    labelNames: ['method', 'route', 'status'],
    registers: [register]
});

const httpRequestDuration = new promClient.Histogram({
    name: 'http_request_duration_seconds',
    help: 'HTTP request duration in seconds',
    labelNames: ['method', 'route'],
    registers: [register]
});

// Create uploads folder if not exists
const uploadDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir);
}

// Middleware
app.use(bodyParser.urlencoded({ extended: true }));
app.use(express.json());
app.use(session({
    secret: 'secret-key',
    resave: false,
    saveUninitialized: true
}));

// Serve uploaded files
app.use('/uploads', express.static(uploadDir));

// Track HTTP metrics
app.use((req, res, next) => {
    const end = httpRequestDuration.startTimer();
    res.on('finish', () => {
        httpRequestCounter.inc({ method: req.method, route: req.path, status: res.statusCode });
        end({ method: req.method, route: req.path });
    });
    next();
});

// Metrics endpoint for Prometheus
app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.send(await register.metrics());
});

// Multer storage config
const storage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, uploadDir);
    },
    filename: function (req, file, cb) {
        cb(null, Date.now() + '-' + file.originalname);
    }
});

const fileFilter = (req, file, cb) => {
    const allowedTypes = /jpg|jpeg|png|pdf|txt/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedTypes.test(file.mimetype);
    if (extname || mimetype) {
        cb(null, true);
    } else {
        cb(new Error('Only jpg, jpeg, png, pdf, txt files are allowed'));
    }
};

const upload = multer({
    storage: storage,
    limits: { fileSize: 5 * 1024 * 1024 },
    fileFilter: fileFilter
});

// Database connection
const db = mysql.createPool({
    connectionLimit: 10,
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || 'new_password',
    database: process.env.DB_NAME || 'loginDB'
});

db.getConnection((err, connection) => {
    if (err) {
        console.error('Database connection error:', err);
    } else {
        console.log('Connected to MySQL database');
        connection.release();
    }
});

// Routes
app.get('/', (req, res) => {
    res.sendFile(__dirname + '/login.html');
});

app.post('/login', (req, res) => {
    const { username, password } = req.body;
    if (!username || !password) {
        return res.status(400).send('Username and password are required');
    }
    db.query('SELECT * FROM users WHERE username = ?', [username], (err, result) => {
        if (err) return res.status(500).send('Error querying database');
        if (result.length === 0) return res.status(400).send('User not found');
        bcrypt.compare(password, result[0].password, (err, isMatch) => {
            if (err) return res.status(500).send('Error checking password');
            if (isMatch) {
                req.session.username = result[0].username;
                return res.send('Login successful');
            }
            return res.status(400).send('Incorrect password');
        });
    });
});

app.get('/dashboard', (req, res) => {
    if (req.session.username) {
        res.send(`
            <h2>Welcome, ${req.session.username}!</h2>
            <form action="/upload" method="POST" enctype="multipart/form-data">
                <input type="file" name="myfile" required />
                <button type="submit">Upload File</button>
            </form>
        `);
    } else {
        res.send('Please log in first.');
    }
});

app.post('/register', (req, res) => {
    const { username, password } = req.body;
    if (!username || !password) {
        return res.status(400).send('Username and password are required');
    }
    bcrypt.hash(password, 10, (err, hash) => {
        if (err) return res.status(500).send('Error hashing password');
        db.query('INSERT INTO users (username, password) VALUES (?, ?)', [username, hash], (err) => {
            if (err) {
                if (err.code === 'ER_DUP_ENTRY') return res.status(400).send('Username already exists');
                return res.status(500).send('Error inserting user');
            }
            res.send('User registered successfully');
        });
    });
});

app.post('/upload', upload.single('myfile'), (req, res) => {
    if (!req.session.username) return res.status(401).send('Please log in first.');
    if (!req.file) return res.status(400).send('No file uploaded');
    res.send(`
        <h3>File uploaded successfully</h3>
        <p>File name: ${req.file.filename}</p>
        <p><a href="/uploads/${req.file.filename}" target="_blank">View File</a></p>
    `);
});

app.use((err, req, res, next) => {
    if (err) return res.status(400).send(err.message);
    next();
});

app.listen(port, () => {
    console.log(`Server running on http://localhost:${port}`);
});
