
//eslint modules
var SourceCode = require("eslint").SourceCode;
var CLIEngine = require("eslint").CLIEngine;
var linter = require('eslint').linter;
var espree = require('espree');

var eslintCLI = new CLIEngine({});

var DEBUG = false;

//default config
var config = {
    ecmaFeatures: {}
};

function _debug() {
    if(DEBUG)
        debug.apply(null, arguments);
} 

function isModule(js) {
    var import_re = /^\s*import\s/m;
    var export_re = /^\s*export\s/m;
    return import_re.test(js) || export_re.test(js);
}

function getConfig(filename) {
    try {
        config = eslintCLI.getConfigForFile(filename);
    } catch (e) {
        _debug("error parsing eslintrc", e)
    }
}

function createFatalErrorMessage(msg) {
    return[{
        fatal: true,
        message: msg,
        severity: 2,
        line: 1,
        column: 1
    }]
}

function getLint(input_js) {
    
    var sourceType = isModule(input_js) ? 'module' : 'script';
    var sourceCode, messages = [];

    try {
    
        var ast = espree.parse(input_js, {
            range: true,
            loc: true,
            tolerant: true,
            tokens: true,
            comments: true,
            attachComment: true,
            ecmaVersion: 6,
            sourceType: sourceType,
            ecmaFeatures:  config.ecmaFeatures   
        });

    } catch (e) {
        return createFatalErrorMessage(e.message);
    }

    try {
        sourceCode = new SourceCode(input_js, ast);
    } catch(e) {
        return createFatalErrorMessage(e.message);
    }

    try {
        messages = linter.verify(sourceCode, config);
    } catch(e) {
        return createFatalErrorMessage(e.message);
    }

    return messages;
}

function getBufferText(nv) {

    //var start = (new Date()).getTime();
    nv.callFunction('ESLint_GetBufferText',[], function (err, res) {

        var messages = [];

        if (err) _debug(err);

        messages = getLint(res);
        
        nv.callFunction('ShowEslintOutput', [JSON.stringify({messages: messages})], function (err, res) {
            if (err) _debug(err);
        });
    });

}

plugin.autocmdSync('FileType', {
    pattern: 'javascript',
    eval: 'expand("%:p")'
}, function (nvim, filepath) {
    getConfig(filepath);
    getBufferText(nvim);
});

plugin.autocmd('User', {
    pattern: 'eslint.lint'
}, getBufferText);

