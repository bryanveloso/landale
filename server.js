"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g;
    return g = { next: verb(0), "throw": verb(1), "return": verb(2) }, typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (_) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
exports.__esModule = true;
var http_1 = require("http");
var next_1 = require("next");
var env_1 = require("@next/env");
var url_1 = require("url");
var socket_controller_1 = require("./lib/socket.controller");
var obs_controller_1 = require("./lib/obs.controller");
(0, env_1.loadEnvConfig)('./', process.env.NODE_ENV !== 'production');
var dev = process.env.NODE_ENV !== 'production';
var hostname = 'localhost';
var port = 8008;
var app = (0, next_1["default"])({ dev: dev, hostname: hostname, port: port });
var handle = app.getRequestHandler();
var url = "http://".concat(hostname, ":").concat(port);
var server;
var listener = function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var parsedUrl, err_1;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 2, , 3]);
                res.server = server;
                parsedUrl = (0, url_1.parse)(req.url, true);
                return [4 /*yield*/, handle(req, res, parsedUrl)];
            case 1:
                _a.sent();
                return [3 /*break*/, 3];
            case 2:
                err_1 = _a.sent();
                console.error("Error occured handling", req.url, err_1);
                res.statusCode = 500;
                res.end('internal server error');
                return [3 /*break*/, 3];
            case 3: return [2 /*return*/];
        }
    });
}); };
var init = function () { return __awaiter(void 0, void 0, void 0, function () {
    var socketController, obsController;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0: return [4 /*yield*/, app.prepare()];
            case 1:
                _a.sent();
                server = (0, http_1.createServer)(listener);
                server.listen(port, function () { return console.log("Ready on ".concat(url)); });
                socketController = new socket_controller_1["default"](server);
                obsController = new obs_controller_1["default"](socketController);
                server.socket = socketController;
                server.obs = obsController;
                return [2 /*return*/];
        }
    });
}); };
init();
