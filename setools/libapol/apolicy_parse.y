/* Copyright (C) 2001-2004 Tresys Technology, LLC
 * see file 'COPYING' for use and warranty information */

/* 
 * Author: mayerf@tresys.com 
 */
 
/* skeleton and structure "borrowed" from SE Linux module\selinux_plug\ss\policy.parse.y */
/* nearly all the logic is new and specific to policy analysis */

/* Keeping track of policy version.  We try to maintain some backwards 
 * comptability so that we can use this libaray with old and new policies.
 * This is difficult since changes are occuring regular to the syntax!
 * Below is our record of the versions we track, and what we think distinguishes them.
 * This is not a complete version determiner; just key issues.
 *
 * Policy Version 16? (POL_VER_16):
 *	Added conditional policy syntax
 *		if-else statement
 *		bool declarations
 *
 * Policy Version 15 (POL_VER_15):
 *	Added FSUSEXATTR 
 *
 * Pre Jul 2002 (POL_VER_11 & POL_VER_12):
 *
 * 	devfs_context syntax
 * 	clone rule
 * 	notify rule (though never used and we don't keep it around)
 * 	fs_context without FSCON keyword
 * 	port context without PORTCON keyword
 * 	net if context without NETIFCON keyword
 * 	node context without NODECON keyword
 *	type attributes wihtout ATTRIBUTE keyword
 *
 * As of Jul 2002:
 *
 *	Type Attributes declared via ATTRIBUTE keyword
 *	clone rule not supported
 *	notify rule not supported
 *	added dontaudit rule
 * 	fs_uses added
 * 	gen_fs (GENFSCON) added; devfs_context removed
 *	PORTCON, FSCON, NETIFCON, and NODECON added, and previous
 *		formats removed
 *
 */
 

%{
#include "queue.h"
#include "policy.h"
#include "cond.h"
#include <assert.h>

queue_t id_queue = 0;
unsigned int pass;

/* our GLOBAL policy structure */
policy_t *parse_policy = NULL;

/* from /usr/include/asm/types.h DAC */
/*#include <types.h> */
typedef unsigned int __u32;

/* from originial constraint.h */
/* Needed by apolicy_parse.y for "borrowed" code */
typedef struct constraint_expr {
#define CEXPR_NOT		1 /* not expr */
#define CEXPR_AND		2 /* expr and expr */
#define CEXPR_OR		3 /* expr or expr */
#define CEXPR_ATTR		4 /* attr op attr */
#define CEXPR_NAMES		5 /* attr op names */	
	__u32 expr_type;	/* expression type */

#define CEXPR_USER 1		/* user */
#define CEXPR_ROLE 2		/* role */
#define CEXPR_TYPE 4		/* type */
#define CEXPR_TARGET 8		/* target if set, source otherwise */
	__u32 attr;		/* attribute */

#define CEXPR_EQ     1		/* == or eq */
#define CEXPR_NEQ    2		/* != */
#define CEXPR_DOM    3		/* dom */
#define CEXPR_DOMBY  4		/* domby  */
#define CEXPR_INCOMP 5		/* incomp */
	__u32 op;		/* operator */
	
/*	ebitmap_t names;*/	/* names */

	struct constraint_expr *left;
	struct constraint_expr *right;

	__u32 count;		/* reference count */
} constraint_expr_t;
/* end from constraint.h */

/* this is for passing around a rule (used in the conditional
 * policy support.
 */
typedef struct rule_desc {
	int rule_type;
	int idx;
} rule_desc_t;

/* used to signify non-error but empty return */
static rule_desc_t dummy_rule_desc;
static cond_expr_t dummy_cond_expr;

extern char yytext[];
extern int yywarn(char *msg);
extern int yyerror(char *msg);
static char errormsg[255];
extern unsigned long policydb_lineno;

static int insert_separator(int push);
static int insert_id(char *id,int push);
static int define_class(void);
static int define_initial_sid(void);
static int define_common_perms(void);
static int define_av_perms(int inherits);
static int define_sens(void);
static int define_dominance(void);
static int define_category(void);
static int define_level(void);
static int define_common_base(void);
static int define_av_base(void);
static int define_attrib(void);
static int define_typealias(void);
static int define_type(int alias);
static int define_compute_type(int rule_type);
static int define_te_clone(void);
static int define_te_avtab(int rule_type);
static int define_role_types(void);
/*static role_datum_t *merge_roles_dom(role_datum_t *r1,role_datum_t *r2);*/
static int define_role_dom(void);
static int define_role_trans(void);
static int define_role_allow(void);
static int define_constraint(void);
static constraint_expr_t *define_cexpr(__u32 expr_type, __u32 arg1, __u32 arg2);
static int define_user(void);
static security_context_t *parse_security_context(int dontsave);
static int define_initial_sid_context(void);
static int define_devfs_context(int has_type);
static int define_fs_context(int ver);
static int define_port_context(int ver);
static int define_netif_context(int ver);
static int define_node_context(int ver);
static int define_fs_use(int behavior, int ver);
static int define_genfs_context(int has_type);
static int define_nfs_context(void);
static int define_bool(void);
static int define_conditional(cond_expr_t *expr, cond_rule_list_t *t_list, cond_rule_list_t *f_list);
static cond_expr_t *define_cond_expr(__u32 expr_type, void *arg1, void *arg2);
static cond_rule_list_t *define_cond_pol_list(cond_rule_list_t *list, rule_desc_t *rule);
static rule_desc_t *define_cond_compute_type(int rule_type);
static rule_desc_t *define_cond_te_avtab(int rule_type);
%}

%union {
	int sval;
	unsigned int val;
	unsigned int *valptr;
	void *ptr;
}

%type <ptr> cond_expr cond_expr_prim cond_pol_list
%type <ptr> cond_allow_def cond_auditallow_def cond_auditdeny_def cond_dontaudit_def
%type <ptr> cond_transition_def cond_te_avtab_def cond_rule_def
%type <sval> role_def roles
%type <sval> cexpr cexpr_prim op roleop
%type <val> ipv4_addr_def number

%token PATH
%token CLONE
%token COMMON
%token CLASS
%token CONSTRAIN
%token INHERITS
%token SID
%token ROLE
%token ROLES
%token TYPEALIAS
%token TYPE
%token TYPES
%token ALIAS
%token ATTRIBUTE
%token BOOL
%token IF
%token ELSE
%token TYPE_TRANSITION
%token TYPE_MEMBER
%token TYPE_CHANGE
%token ROLE_TRANSITION
%token SENSITIVITY
%token DOMINANCE
%token DOM DOMBY INCOMP
%token CATEGORY
%token LEVEL
%token RANGES
%token USER
%token NEVERALLOW
%token ALLOW
%token AUDITALLOW
%token AUDITDENY
%token DONTAUDIT
%token SOURCE
%token TARGET
%token SAMEUSER
%token FSCON PORTCON NETIFCON NODECON 
%token FSUSEPSID FSUSETASK FSUSETRANS FSUSEXATTR
%token GENFSCON
%token U1 U2 R1 R2 T1 T2
%token NOT AND OR XOR
%token CTRUE CFALSE
%token IDENTIFIER
%token USER_IDENTIFIER
%token NUMBER
%token EQUALS
%token NOTEQUAL

%left OR
%left XOR
%left AND
%right NOT
%left EQUALS NOTEQUAL
%%
policy			: classes initial_sids access_vectors 
                          { /*do nothing */ }
			  opt_mls te_rbac users opt_constraints 
			  { /*do nothing */ } 
			  initial_sid_contexts  
			  { /*do nothing*/}
			  policy_version_contexts
			  { /* determine which policy version and
			  	branch accordingly */ }
			;
classes			: class_def 
			| classes class_def
			;
class_def		: CLASS identifier
			{if (define_class()) return -1;}
			;
initial_sids 		: initial_sid_def 
			| initial_sids initial_sid_def
			;
initial_sid_def		: SID identifier
                        {if (define_initial_sid()) return -1;}
			;
access_vectors		: opt_common_perms av_perms
			;
/* added Jul 2002 */
opt_common_perms        : common_perms
                        |
                        ;
common_perms		: common_perms_def
			| common_perms common_perms_def
			;
common_perms_def	: COMMON identifier '{' identifier_list '}'
			{if (define_common_perms()) return -1;}
			;
av_perms		: av_perms_def
			| av_perms av_perms_def
			;
av_perms_def		: CLASS identifier '{' identifier_list '}'
			{if (define_av_perms(FALSE)) return -1;}
                        | CLASS identifier INHERITS identifier 
			{if (define_av_perms(TRUE)) return -1;}
                        | CLASS identifier INHERITS identifier '{' identifier_list '}'
			{if (define_av_perms(TRUE)) return -1;}
			;
opt_mls			: mls
                        | 
			;
mls			: sensitivities dominance opt_categories levels base_perms
			;
sensitivities	 	: sensitivity_def 
			| sensitivities sensitivity_def
			;
sensitivity_def		: SENSITIVITY identifier alias_def ';'
			{if (define_sens()) return -1;}
			| SENSITIVITY identifier ';'
			{if (define_sens()) return -1;}
	                ;
alias_def		: ALIAS names
			;
dominance		: DOMINANCE identifier 
			{if (define_dominance()) return -1;}
                        | DOMINANCE '{' identifier_list '}' 
			{if (define_dominance()) return -1;}
			;
/* added Jul 2002 */
opt_categories          : categories
                        |
                        ;
categories 		: category_def 
			| categories category_def
			;
category_def		: CATEGORY identifier alias_def ';'
			{if (define_category()) return -1;}
			| CATEGORY identifier ';'
			{if (define_category()) return -1;}
			;
levels	 		: level_def 
			| levels level_def
			;
level_def		: LEVEL identifier ':' id_comma_list ';'
			{if (define_level()) return -1;}
			| LEVEL identifier ';' 
			{if (define_level()) return -1;}
			;
base_perms		: opt_common_base av_base
			;
/* added Jul 2002 */
opt_common_base         : common_base
                        |
                        ;
common_base		: common_base_def
			| common_base common_base_def
			;
common_base_def	        : COMMON identifier '{' perm_base_list '}'
	                {if (define_common_base()) return -1;}
			;
av_base		        : av_base_def
			| av_base av_base_def
			;
av_base_def		: CLASS identifier '{' perm_base_list '}'
	                {if (define_av_base()) return -1;}
                        | CLASS identifier
	                {if (define_av_base()) return -1;}
			;
perm_base_list		: perm_base
			| perm_base_list perm_base
			;
perm_base		: identifier ':' identifier
			{if (insert_separator(0)) return -1;}
                        | identifier ':' '{' identifier_list '}'
			{if (insert_separator(0)) return -1;}
			;
te_rbac			: te_rbac_decl
			| te_rbac te_rbac_decl
			;
te_rbac_decl		: te_decl
			| rbac_decl
			| ';'
                        ;

rbac_decl		: role_type_def
                        | role_dominance
                        | role_trans_def
 			| role_allow_def
			;
			/* added July 2002; we make optional for backwards compatability */
			/* added optional conditional language stuff */
te_decl			: opt_attribute_def
			| opt_cond_def
			| type_def
			| typealias_def
                        | transition_def
                        | te_avtab_def
                        /* removed July 2002; remain for backward compatability */
			| te_clone_def
			;
/* our addition Jul 2002, for to allow for no attribute_def for backwards compatablity */
opt_attribute_def	: attribute_def
			|
			;
/*  added July 2002 */
attribute_def           : ATTRIBUTE identifier ';'
                        { if (define_attrib()) return -1;}
                        ;
                        
/* support for conditional policy language extensions */
opt_cond_def		: bool_def
			| cond_stmt_def
			|
			;
bool_def                : BOOL identifier bool_val ';'
                        {if (define_bool()) return -1;}
                        ;
bool_val                : CTRUE
 			{ if (insert_id("T",0)) return -1; }
                        | CFALSE
			{ if (insert_id("F",0)) return -1; }
                        ;
cond_stmt_def           : IF cond_expr '{' cond_pol_list '}'
                        { if (define_conditional((cond_expr_t*)$2, (cond_rule_list_t*)$4, (cond_rule_list_t*)NULL) < 0) return -1; }
                        | IF cond_expr '{' cond_pol_list '}' ELSE '{' cond_pol_list '}'
                        { if (define_conditional((cond_expr_t*)$2, (cond_rule_list_t*)$4, (cond_rule_list_t*)$8) < 0 ) return -1;  }
                        ;
cond_expr               : '(' cond_expr ')'
			{ $$ = $2;}
			| NOT cond_expr
			{ $$ = define_cond_expr(COND_NOT, $2, NULL);
			  if ($$ == NULL) return -1; }
			| cond_expr AND cond_expr
			{ $$ = define_cond_expr(COND_AND, $1, $3);
			  if ($$ == NULL) return -1; }
			| cond_expr OR cond_expr
			{ $$ = define_cond_expr(COND_OR, $1, $3);
			  if ($$ == NULL) return -1; }
			| cond_expr XOR cond_expr
			{ $$ = define_cond_expr(COND_XOR, $1, $3);
			  if ($$ == NULL) return -1; }
			| cond_expr EQUALS cond_expr
			{ $$ = define_cond_expr(COND_EQ, $1, $3);
			  if ($$ == NULL) return -1; }
			| cond_expr NOTEQUAL cond_expr
			{ $$ = define_cond_expr(COND_NEQ, $1, $3);
			  if ($$ == NULL) return -1; }
			| cond_expr_prim
			{ $$ = $1; }
			;
cond_expr_prim          : identifier
                        { $$ = define_cond_expr(COND_BOOL, NULL, NULL);
			  if ($$ == NULL) return -1; }
                        ;
cond_pol_list           : cond_rule_def
                        { $$ = define_cond_pol_list((cond_rule_list_t*)NULL, (rule_desc_t*)$1);
			  if ($$ == 0) return -1; }
                        | cond_pol_list cond_rule_def 
                        { $$ = define_cond_pol_list((cond_rule_list_t*)$1, (rule_desc_t*)$2);
			  if ($$ == 0) return -1; }
			;
cond_rule_def           : cond_transition_def
                        { $$ = $1;
			  if ($$ == NULL) return -1; }
                        | cond_te_avtab_def
                        { $$ = $1;
			  if ($$ == NULL) return -1; }
                        ;
cond_transition_def	: TYPE_TRANSITION names names ':' names identifier ';'
                        { $$ = define_cond_compute_type(RULE_TE_TRANS) ;
                          if ($$ == 0) return -1;}
                        | TYPE_MEMBER names names ':' names identifier ';'
                        { $$ = define_cond_compute_type(RULE_TE_MEMBER) ;
                          if ($$ ==  0) return -1;}
                        | TYPE_CHANGE names names ':' names identifier ';'
                        { $$ = define_cond_compute_type(RULE_TE_CHANGE) ;
                          if ($$ ==  0) return -1;}
    			;
cond_te_avtab_def	: cond_allow_def
                          { $$ = $1; }
			| cond_auditallow_def
			  { $$ = $1; }
			| cond_auditdeny_def
			  { $$ = $1; }
			| cond_dontaudit_def
			  { $$ = $1; }
			;
cond_allow_def		: ALLOW names names ':' names names  ';'
			{ $$ = define_cond_te_avtab(RULE_TE_ALLOW) ;
                          if ($$ == 0) return -1; }
		        ;
cond_auditallow_def	: AUDITALLOW names names ':' names names ';'
			{ $$ = define_cond_te_avtab(RULE_AUDITALLOW) ;
                          if ($$ == 0) return -1; }
		        ;
cond_auditdeny_def	: AUDITDENY names names ':' names names ';'
			{ $$ = define_cond_te_avtab(RULE_AUDITDENY) ;
                          if ($$ == 0) return -1; }
		        ;
cond_dontaudit_def	: DONTAUDIT names names ':' names names ';'
			{ $$ = define_cond_te_avtab(RULE_DONTAUDIT);
                          if ($$ == 0) return -1; }
                        ;


/* removed July 2002; remain for backward compatability */
te_clone_def            : CLONE identifier identifier ';'
			{if (define_te_clone()) return -1;}
			;
type_def		: TYPE identifier alias_def opt_attr_list ';'
                        {if (define_type(1)) return -1;}
	                | TYPE identifier opt_attr_list ';'
                        {if (define_type(0)) return -1;}
    			;
/* added feb 2004 */			
typealias_def		: TYPEALIAS identifier alias_def ';'
			{if (define_typealias()) return -1;}
			;
opt_attr_list           : ',' id_comma_list
			| 
			;
transition_def		: TYPE_TRANSITION names names ':' names identifier ';'
                        {if (define_compute_type(RULE_TE_TRANS)) return -1;}
                        | TYPE_MEMBER names names ':' names identifier ';'
                        {if (define_compute_type(RULE_TE_MEMBER)) return -1;}
                        | TYPE_CHANGE names names ':' names identifier ';'
                        {if (define_compute_type(RULE_TE_CHANGE)) return -1;}
    			;
te_avtab_def		: allow_def
			| auditallow_def
			| auditdeny_def
			/* Jul 2002, removed notify and added dontaudit */
			| dontaudit_def
			| neverallow_def
			;
allow_def		: ALLOW names names ':' names names  ';'
			{if (define_te_avtab(RULE_TE_ALLOW)) return -1; }
		        ;
auditallow_def		: AUDITALLOW names names ':' names names ';'
			{if (define_te_avtab(RULE_AUDITALLOW)) return -1; }
		        ;
auditdeny_def		: AUDITDENY names names ':' names names ';'
			{if (define_te_avtab(RULE_AUDITDENY)) return -1; }
		        ;
/* Jul 2002, removed notify and added dontaudit */
dontaudit_def		: DONTAUDIT names names ':' names names ';'
			{if (define_te_avtab(RULE_DONTAUDIT)) return -1; }
		        ;
neverallow_def		: NEVERALLOW names names ':' names names  ';'
			{if (define_te_avtab(RULE_NEVERALLOW)) return -1; }
		        ;
role_type_def		: ROLE identifier TYPES names ';'
			{if (define_role_types()) return -1;}
                        ;
role_dominance		: DOMINANCE '{' roles '}'
			;
role_trans_def		: ROLE_TRANSITION names names identifier ';'
			{if (define_role_trans()) return -1; }
			;
role_allow_def		: ALLOW names names ';'
			{if (define_role_allow()) return -1; }
			;
roles			: role_def
			{ $$ = $1; }
			| roles role_def
			{ /* do nothing */}
			;
role_def		: ROLE identifier_push ';'
                        {$$ = define_role_dom(); if ($$ == 0) return -1;}
			| ROLE identifier_push '{' roles '}'
                        {$$ = define_role_dom(); if ($$ == 0) return -1;}
			;
/* added July 2002; made constraints optional */
opt_constraints         : constraints
                        |
                        ;

constraints		: constraint_def
			| constraints constraint_def
			;
constraint_def		: CONSTRAIN names names cexpr ';'
			{ if (define_constraint()) return -1; }
			;
cexpr			: '(' cexpr ')'
			{ $$ = $2; }
			| NOT cexpr
			{ $$ = (int) define_cexpr(CEXPR_NOT, $2, 0);
			  if ($$ == 0) return -1; }
			| cexpr AND cexpr
			{ $$ = (int) define_cexpr(CEXPR_AND, $1, $3);
			  if ($$ == 0) return -1; }
			| cexpr OR cexpr
			{ $$ = (int) define_cexpr(CEXPR_OR, $1, $3);
			  if ($$ == 0) return -1; }
			| cexpr_prim
			{ $$ = $1; }
			;
cexpr_prim		: U1 op U2
			{ $$ = (int) define_cexpr(CEXPR_ATTR, CEXPR_USER, $2);
			  if ($$ == 0) return -1; }
			| R1 roleop R2
			{ $$ = (int) define_cexpr(CEXPR_ATTR, CEXPR_ROLE, $2);
			  if ($$ == 0) return -1; }
			| T1 op T2
			{ $$ = (int) define_cexpr(CEXPR_ATTR, CEXPR_TYPE, $2);
			  if ($$ == 0) return -1; }
			| U1 op { if (insert_separator(1)) return -1; } user_names_push
			{ $$ = (int) define_cexpr(CEXPR_NAMES, CEXPR_USER, $2);
			  if ($$ == 0) return -1; }
			| U2 op { if (insert_separator(1)) return -1; } user_names_push
			{ $$ = (int) define_cexpr(CEXPR_NAMES, CEXPR_USER | CEXPR_TARGET, $2);
			  if ($$ == 0) return -1; }
			| R1 op { if (insert_separator(1)) return -1; } names_push
			{ $$ = (int) define_cexpr(CEXPR_NAMES, CEXPR_ROLE, $2);
			  if ($$ == 0) return -1; }
			| R2 op { if (insert_separator(1)) return -1; } names_push
			{ $$ = (int) define_cexpr(CEXPR_NAMES, CEXPR_ROLE | CEXPR_TARGET, $2);
			  if ($$ == 0) return -1; }
			| T1 op { if (insert_separator(1)) return -1; } names_push
			{ $$ = (int) define_cexpr(CEXPR_NAMES, CEXPR_TYPE, $2);
			  if ($$ == 0) return -1; }
			| T2 op { if (insert_separator(1)) return -1; } names_push
			{ $$ = (int) define_cexpr(CEXPR_NAMES, CEXPR_TYPE | CEXPR_TARGET, $2);
			  if ($$ == 0) return -1; }
			| SAMEUSER
			{ $$ = (int) define_cexpr(CEXPR_ATTR, CEXPR_USER, CEXPR_EQ);
			  if ($$ == 0) return -1; }
			| SOURCE ROLE { if (insert_separator(1)) return -1; } names_push
			{ $$ = (int) define_cexpr(CEXPR_NAMES, CEXPR_ROLE, CEXPR_EQ);
			  if ($$ == 0) return -1; }
			| TARGET ROLE { if (insert_separator(1)) return -1; } names_push
			{ $$ = (int) define_cexpr(CEXPR_NAMES, CEXPR_ROLE | CEXPR_TARGET, CEXPR_EQ);
			  if ($$ == 0) return -1; }
			| ROLE roleop
			{ $$ = (int) define_cexpr(CEXPR_ATTR, CEXPR_ROLE, $2);
			  if ($$ == 0) return -1; }
			| SOURCE TYPE { if (insert_separator(1)) return -1; } names_push
			{ $$ = (int) define_cexpr(CEXPR_NAMES, CEXPR_TYPE, CEXPR_EQ);
			  if ($$ == 0) return -1; }
			| TARGET TYPE { if (insert_separator(1)) return -1; } names_push
			{ $$ = (int) define_cexpr(CEXPR_NAMES, CEXPR_TYPE | CEXPR_TARGET, CEXPR_EQ);
			  if ($$ == 0) return -1; }
			;
op			: EQUALS
			{ $$ = CEXPR_EQ; }
			| NOTEQUAL
			{ $$ = CEXPR_NEQ; }
			;
roleop			: op 
			{ $$ = $1; }
			| DOM
			{ $$ = CEXPR_DOM; }
			| DOMBY
			{ $$ = CEXPR_DOMBY; }
			| INCOMP
			{ $$ = CEXPR_INCOMP; }
			;
users			: user_def
			| users user_def
			;
user_id			: identifier
			| user_identifier
			;
user_def		: USER user_id ROLES names opt_user_ranges ';'
	                {if (define_user()) return -1;}
			;
opt_user_ranges		: RANGES user_ranges 
			|
			;
user_ranges		: mls_range_def
			| '{' user_range_def_list '}' 
			;
user_range_def_list	: mls_range_def
			| user_range_def_list mls_range_def
			;
initial_sid_contexts	: initial_sid_context_def
			| initial_sid_contexts initial_sid_context_def
			;
initial_sid_context_def	: SID identifier security_context_def
			{if (define_initial_sid_context()) return -1;}
			;

/* added Jul 2002 to maintain backwards compatabililty with previous
 * policy versions 
 *
 * current distinctions are:
 * pre_jul_2002		policy versions prior to version 11
 * jul_2002		policy version 11 or later
 */			
policy_version_contexts	: version_jul_2002
			| versions_pre_jul_2002
			;

version_jul_2002	: opt_fs_contexts_11 fs_uses opt_genfs_contexts 
				net_contexts_11
			;
			
versions_pre_jul_2002	: fs_contexts_pre11
			  opt_devfs_contexts { /* this is a new policy component added in the
			                      May 2002 release of SE Linux.  We are making this
			                      optional so that apolicy will (for now at least)
			                      work wih older policies as well as newer ones */ }
			  net_contexts_pre11
			;


/* added Jul 2002 */
fs_uses                 : fs_use_def
                        | fs_uses fs_use_def
                        ;
/* added Jul 2002 */
/* changed Jul 2003; added FSUSEXATTR */
fs_use_def              : FSUSEPSID identifier ';' 
                        {if (define_fs_use(0, POL_VER_JUL2002)) return -1;}
                        | FSUSEXATTR identifier security_context_def ';'
                        {if (define_fs_use(1, POL_VER_15)) return -1;}
                        | FSUSETASK identifier security_context_def ';'
                        {if (define_fs_use(1, POL_VER_JUL2002)) return -1;}
                        | FSUSETRANS identifier security_context_def ';'
                        {if (define_fs_use(1, POL_VER_JUL2002)) return -1;}
                        ; 
/* added Jul 2002 */                       
opt_genfs_contexts      : genfs_contexts
                        | 
                        ;
/* added Jul 2002 */ 
genfs_contexts	        : genfs_context_def
			| genfs_contexts genfs_context_def
			;
/* added Jul 2002 */ 
genfs_context_def	: GENFSCON identifier path '-' identifier security_context_def
			{if (define_genfs_context(1)) return -1;}
			| GENFSCON identifier path '-' '-' {insert_id("-", 0);} security_context_def
			{if (define_genfs_context(1)) return -1;}
                        | GENFSCON identifier path security_context_def
			{if (define_genfs_context(0)) return -1;}
			;


/* added Jul 2002 */
opt_fs_contexts_11      : fs_contexts_11 
                        |
                        ;
fs_contexts_11		: fs_context_def_11
			| fs_contexts_11 fs_context_def_11
			;
			
fs_contexts_pre11	: fs_context_def_pre11
			| fs_contexts_pre11 fs_context_def_pre11
			;
/* changed Jul 2002, added FSCON keyword */
fs_context_def_11	: FSCON number number security_context_def security_context_def
			{if (define_fs_context(POL_VER_JUL2002)) return -1;}
			;
/* removed Jul 2002, keep for backward compatability */
fs_context_def_pre11	: number number security_context_def security_context_def
			{if (define_fs_context(POL_VER_PREJUL2002)) return -1;}
			;

/* net_context versions */
net_contexts_11		: opt_port_contexts_11 opt_netif_contexts_11 opt_node_contexts_11 
			;
net_contexts_pre11	: port_contexts_pre11 netif_contexts_pre11 node_contexts_pre11 opt_nfs_contexts
			;

/* added Jul 2002 */
opt_port_contexts_11  	: port_contexts_11
                        |
                        ;
port_contexts_11	: port_context_def_11
			| port_contexts_11 port_context_def_11
			;
			
/* changed Jul 2002 to add PORTCON keyword */
port_context_def_11	: PORTCON identifier number security_context_def
			{if (define_port_context(POL_VER_JUL2002)) return -1;}
			| PORTCON identifier number '-' number security_context_def
			{if (define_port_context(POL_VER_JUL2002)) return -1;}
			;
/* removed in Jul 2002; keep to allow old form for backwards compatability */
port_contexts_pre11	: port_context_def_pre11
			| port_contexts_pre11 port_context_def_pre11
			;
port_context_def_pre11	: identifier number security_context_def
			{if (define_port_context(POL_VER_PREJUL2002)) return -1;}
			| identifier number '-' number security_context_def
			{if (define_port_context(POL_VER_PREJUL2002)) return -1;}
			;
/* added Jul 2002 */
opt_netif_contexts_11   : netif_contexts_11
                        |
                        ;
/* changed Jul 2002 to add NETIFCON keyword */
netif_contexts_11	: netif_context_def_11
			| netif_contexts_11 netif_context_def_11
			;
netif_context_def_11	: NETIFCON identifier security_context_def security_context_def
			{if (define_netif_context(POL_VER_JUL2002)) return -1;} 
			;
/* removed in Jul 2002; keep to allow old form for backwards compatability */
netif_contexts_pre11	: netif_context_def_pre11
			| netif_contexts_pre11 netif_context_def_pre11 
			;
netif_context_def_pre11	: identifier security_context_def security_context_def
			{if (define_netif_context(POL_VER_PREJUL2002)) return -1;}
			;
/* added Jul 2002 */
opt_node_contexts_11   	: node_contexts_11 
                        |
                        ;
node_contexts_11	: node_context_def_11
			| node_contexts_11 node_context_def_11
			;
/* changed Jul 2002 to add NODECON keyword */
node_context_def_11	: NODECON ipv4_addr_def ipv4_addr_def security_context_def
			{if (define_node_context(POL_VER_JUL2002)) return -1;}
			;
/* Jul 2002, allow for old form for backwards compatability */
node_contexts_pre11	: node_context_def_pre11
			| node_contexts_pre11 node_context_def_pre11 
			;
/* removed in Jul 2002; keep to allow old form for backwards compatability */
node_context_def_pre11	: ipv4_addr_def ipv4_addr_def security_context_def
			{if (define_node_context(POL_VER_PREJUL2002)) return -1;}
			;
/* all NFS remove Jul 2002 */
opt_nfs_contexts        : nfs_contexts
                        |
                        ;
nfs_contexts		: nfs_context_def
			| nfs_contexts nfs_context_def
			;
nfs_context_def	        : ipv4_addr_def ipv4_addr_def security_context_def security_context_def
			{if (define_nfs_context()) return -1;}
			;

/* removed Jul 2002 */
opt_devfs_contexts	: devfs_contexts
			|
			;
/* removed Jul 2002 */
devfs_contexts		: devfs_context_def 
			| devfs_contexts devfs_context_def
			;
/* removed Jul 2002 */
devfs_context_def	: path '-' identifier security_context_def
			{if (define_devfs_context(1)) return -1;}
                        | path security_context_def
			{if (define_devfs_context(0)) return -1;}
			;
ipv4_addr_def		: number '.' number '.' number '.' number
			{ 
			  /*do nothing*/
			}
    			;
security_context_def	: user_id ':' identifier ':' identifier opt_mls_range_def
	                ;
opt_mls_range_def	: ':' mls_range_def
			|	
			;
mls_range_def		: mls_level_def '-' mls_level_def
			{if (insert_separator(0)) return -1;}
	                | mls_level_def
			{if (insert_separator(0)) return -1;}
	                ;
mls_level_def		: identifier ':' id_comma_list
			{if (insert_separator(0)) return -1;}
	                | identifier 
			{if (insert_separator(0)) return -1;}
	                ;
id_comma_list           : identifier
			| id_comma_list ',' identifier
			;
tilde			: '~'
			;
asterisk		: '*'
                        ;
exclude                 : '-'

/* Jul 2002 nesting logic changed slightly */			;
names           	: identifier
			{ if (insert_separator(0)) return -1; }
			| nested_id_set
			{ if (insert_separator(0)) return -1; }
			| asterisk
                        { if (insert_id("*", 0)) return -1; 
			  if (insert_separator(0)) return -1; }
			| tilde identifier
                        { if (insert_id("~", 0)) return -1;
			  if (insert_separator(0)) return -1; }
                        | identifier exclude { if (insert_id("-", 0)) return -1; } identifier
                        { if (insert_separator(0)) return -1; }
			| tilde nested_id_set
	 		{ if (insert_id("~", 0)) return -1; 
			  if (insert_separator(0)) return -1; }
			;
tilde_push              : tilde
                        { if (insert_id("~", 1)) return -1; }
			;
asterisk_push           : asterisk
                        { if (insert_id("*", 1)) return -1; }
			;
names_push		: identifier_push
			| '{' identifier_list_push '}'
			| asterisk_push
			| tilde_push identifier_push
			| tilde_push '{' identifier_list_push '}'
			;
identifier_list_push	: identifier_push
			| identifier_list_push identifier_push
			;
identifier_push		: IDENTIFIER
			{ if (insert_id(yytext, 1)) return -1; }
			;
identifier_list		: identifier
			| identifier_list identifier
			;
/* added Jul 2002*/
nested_id_set           : '{' nested_id_list '}'
                        ;
nested_id_list          : nested_id_element | nested_id_list nested_id_element
                        ;
nested_id_element       : identifier | '-' { if (insert_id("-", 0)) return -1; } identifier | nested_id_set
			;
/* end add */
identifier		: IDENTIFIER
			{ if (insert_id(yytext,0)) return -1; }
			;
user_identifier		: USER_IDENTIFIER
			{ if (insert_id(yytext,0)) return -1; }
			;
user_identifier_push	: USER_IDENTIFIER
			{ if (insert_id(yytext, 1)) return -1; }
			;
user_identifier_list_push : user_identifier_push
			| identifier_list_push user_identifier_push
			| user_identifier_list_push identifier_push
			| user_identifier_list_push user_identifier_push
			;
user_names_push		: names_push
			| user_identifier_push
			| '{' user_identifier_list_push '}'
			| tilde_push user_identifier_push
			| tilde_push '{' user_identifier_list_push '}'
			;
path     		: PATH
			{ if (insert_id(yytext,0)) return -1; }
			;
number			: NUMBER 
			{ $$ = strtoul(yytext,NULL,0); }
			;
%%
static int insert_separator(int push)
{
	int error;

	if (push)
		error = queue_push(id_queue, 0);
	else
		error = queue_insert(id_queue, 0);

	if (error) {
		yyerror("queue overflow");
		return -1;
	}
	return 0;
}

static int insert_id(char *id, int push)
{
	char *newid = 0;
	int error;

	newid = (char *) malloc(strlen(id) + 1);
	if (!newid) {
		yyerror("out of memory");
		return -1;
	}
	strcpy(newid, id);
	if (push)
		error = queue_push(id_queue, (queue_element_t) newid);
	else
		error = queue_insert(id_queue, (queue_element_t) newid);

	if (error) {
		yyerror("queue overflow");
		free(newid);
		return -1;
	}
	return 0;
}

/* added with Jul 2002 policy changes; allows for explicit declarations of type attributes */
static int define_attrib(void)
{
	char *id;
	int rt;
	
	rt = set_policy_version(POL_VER_JUL2002, parse_policy);
	if(rt != 0) {
		yyerror("error setting policy version");
		return -1;
	}
	if (pass == 2 ||(pass == 1 && !(parse_policy->opts & POLOPT_TYPES))) {
		free(queue_remove(id_queue));
		return 0;
	}
	id = queue_remove(id_queue);
	/* check whether already exists */
	rt = get_attrib_idx(id, parse_policy);
	if(rt >=0){
		sprintf(errormsg, "duplicate class decalaration (%s)\n", id);
		yyerror(errormsg);
		return -1;
	}
	if(!is_valid_str_sz(id)) {
		sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
		yyerror(errormsg);
		return -1;
	}
	rt = add_attrib(FALSE, 0, parse_policy, id);
	if(rt == -1) {
		yyerror("Error adding attribute via ATTRIBUTE keyword");
		return -1;
	}
	free(id);
	return 0;
}
	

static int define_type(int alias)
{
	char *id;
	int idx;

	if (pass == 2 ||(pass == 1 && !(parse_policy->opts & POLOPT_TYPES))) {
		while ((id = queue_remove(id_queue))) 
			free(id);
		/* change in 2002031409 version for alias syntax */
		if (alias) {
			while ((id = queue_remove(id_queue))) 
				free(id);
		}
		return 0;
	}
	
	/* On first call we add the psuedo type 'self' to the list as the first entry */
	if(parse_policy->num_types == 0) {
		id = (char *)malloc(5);
		if(id == NULL) {
			yyerror("out of memory");
			return -1;
		}
		strcpy(id, "self");
		idx = add_type(id, parse_policy);
		if(idx < 0)
			return -1;
	}


	/* add the new type */
	id = (char *) queue_remove(id_queue);
	if (!id) {
		yyerror("no type name for type definition?");
		return -1;
	}
	if(!is_valid_str_sz(id)) {
		sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
		yyerror(errormsg);
		return -1;
	}
	idx = add_type(id, parse_policy);
	if(idx == -2) {
		sprintf(errormsg, "duplicate type decalaration (%s)\n", id);
		yyerror(errormsg);
		return -1;
	}
	else if(idx < 0)
		return -1;	
			
	/* aliases */
	if (alias) { 
		while ((id = queue_remove(id_queue))) {
			if(!is_valid_str_sz(id)) {
				sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
				yyerror(errormsg);
				return -1;
			}
			if(add_alias(idx, id, parse_policy) != 0) {
				sprintf(errormsg, "failed add_name for alias %s\n", id);
				yyerror(errormsg);
				return -1;			
			}
		}
	}
	
	/*  attribs */
	while ((id = queue_remove(id_queue))) {
		if(!is_valid_str_sz(id)) {
			sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
			yyerror(errormsg);
			return -1;
		}
		if(add_attrib_to_type(idx, id, parse_policy) != 0)
			return -1;
	}
	return 0;
}	

static int define_typealias(void)
{
	char *id;
	int idx, idx_type;
	
	if (pass == 2) {
		while ((id = queue_remove(id_queue)))
			free(id);
		return 0;
	}
	
	id = (char*)queue_remove(id_queue);
	if (!id) {
		yyerror("type name required for typealias declaration");
		return -1;
	}
	idx = get_type_or_attrib_idx(id, &idx_type, parse_policy);
	if (idx < 0) {
		sprintf(errormsg, "unknown type %s in typealias definitition.", id);
		yyerror(errormsg);
		return -1;
	}
	if (idx_type != IDX_TYPE) {
		sprintf(errormsg, "%s is not a type. Illegal typealias definitition.", id);
		yyerror(errormsg);
		return -1;
	}
	while ((id = queue_remove(id_queue))) {
		if(!is_valid_str_sz(id)) {
			sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
			yyerror(errormsg);
			return -1;
		}
		if(add_alias(idx, id, parse_policy) != 0) {
			sprintf(errormsg, "failed add_alias for alias %s\n", id);
			yyerror(errormsg);
			return -1;			
		}
	}
	return 0;
}

/* add a rule to the provided av rule list */
static int add_avrule(int type, av_item_t **rlist, int *list_num, bool_t enabled) {
	int idx, idx_type, *sz;
	char *id;
	av_item_t *item;
	ta_item_t *titem;
	bool_t subtract;

	if(type == RULE_TE_ALLOW ||type == RULE_NEVERALLOW) 
		sz = &(parse_policy->list_sz[POL_LIST_AV_ACC]);
	else
		sz = &(parse_policy->list_sz[POL_LIST_AV_AU]);
		
	if (*list_num >= *sz) {
		/* grow the dynamic array */
		av_item_t * ptr;		
		ptr = (av_item_t *)realloc(*rlist, (LIST_SZ + *sz) * sizeof(av_item_t));
		if(ptr == NULL) {
			yyerror("out of memory\n");
			return -1;
		}
		*rlist = ptr;
		*sz += LIST_SZ;
	}	
	
	item = &((*rlist)[*list_num]);
	memset(item, 0, sizeof(av_item_t));
	item->type = type;
	item->lineno = policydb_lineno;
	item->enabled = enabled;

	/* source (domain) types/attribs */
	subtract = FALSE;
	while ((id = queue_remove(id_queue))) {
		if(strcmp(id, "*") == 0) {
			item->flags |= AVFLAG_SRC_STAR;
			free(id);
			continue;
		}
		if(strcmp(id, "-") == 0) {
			subtract = TRUE;
			free(id);
			continue;
		}
		if(strcmp(id, "~") == 0) {
			item->flags |= AVFLAG_SRC_TILDA;
			free(id);
			continue;
		}
		idx = get_type_or_attrib_idx(id, &idx_type, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "%s is neither a type nor type attribute", id);
			yyerror(errormsg);
			return -1;				
		}
		titem = (ta_item_t *)malloc(sizeof(ta_item_t));
		if(titem == NULL) {
			yyerror("out of memory");
			return -1;
		}
		titem->type = idx_type;
		if (subtract) {
			titem->type |= IDX_SUBTRACT;
			subtract = FALSE;
		}
		titem->idx = idx;
		if(insert_ta_item(titem, &(item->src_types)) != 0) {
			sprintf(errormsg, "failed ta_item insetion for source type id %s", id);
			yyerror(errormsg);
			return -1;
		}
		free(id);
	}
	
	/* target object types/attribs */
	subtract = FALSE;
	while ((id = queue_remove(id_queue))) {
		if(strcmp(id, "*") == 0) {
			item->flags |= AVFLAG_TGT_STAR;
			free(id);
			continue;
		}
		if(strcmp(id, "-") == 0) {
			subtract = TRUE;
			free(id);
			continue;
		}
		if(strcmp(id, "~") == 0) {
			item->flags |= AVFLAG_TGT_TILDA;
			free(id);
			continue;
		}	
		idx = get_type_or_attrib_idx(id, &idx_type, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "%s is neither a type or type attribute", id);
			yyerror(errormsg);
			return -1;				
		}
		titem = (ta_item_t *)malloc(sizeof(ta_item_t));
		if(titem == NULL) {
			yyerror("out of memory");
			return -1;
		}
		titem->type = idx_type;
		if (subtract) {
			titem->type |= IDX_SUBTRACT;
			subtract = FALSE;
		}
		titem->idx = idx;
		if(insert_ta_item(titem, &(item->tgt_types)) != 0) {
			sprintf(errormsg, "failed ta_item insetion for target type id %s", id);
			yyerror(errormsg);
			return -1;
		}
		free(id);
	}		
	/* object classes */
	while ((id = queue_remove(id_queue))) {
		if(strcmp(id, "*") == 0) {
			item->flags |= AVFLAG_CLS_STAR;
			free(id);
			continue;
		}
		if(strcmp(id, "~") == 0) {
			item->flags |= AVFLAG_CLS_TILDA;
			free(id);
			continue;
		}
		idx = get_obj_class_idx(id, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "%s is not a valid object class name", id);
			yyerror(errormsg);
			return -1;
		}
		titem = (ta_item_t *)malloc(sizeof(ta_item_t));
		if(titem == NULL) {
			yyerror("out of memory");
			return -1;
		}
		titem->type = IDX_OBJ_CLASS;
		titem->idx = idx;
		if(insert_ta_item(titem, &(item->classes)) != 0) {
			sprintf(errormsg, "failed ta_item insetion for classes id %s", id);
			yyerror(errormsg);
			return -1;
		}
		free(id);
	}
	
	/* permissions */
	while ((id = queue_remove(id_queue))) {
		if(strcmp(id, "*") == 0) {
			item->flags |= AVFLAG_PERM_STAR;
			free(id);
			continue;
		}
		if(strcmp(id, "~") == 0) {
			item->flags |= AVFLAG_PERM_TILDA;
			free(id);
			continue;
		}
		idx = get_perm_idx(id, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "%s is not a valid permission name", id);
			yyerror(errormsg);
			return -1;
		}
		titem = (ta_item_t *)malloc(sizeof(ta_item_t));
		if(titem == NULL) {
			yyerror("out of memory");
			return -1;
		}
		titem->type = IDX_PERM;
		titem->idx = idx;
		if(insert_ta_item(titem, &(item->perms)) != 0) {
			sprintf(errormsg, "failed ta_item insetion for classes id %s", id);
			yyerror(errormsg);
			return -1;
		}
		free(id);
	}	

	(*list_num)++;
	return *list_num - 1;
}

/* store av rules */
static int define_te_avtab(int rule_type)
{
	int rt;
	char *id;

	if (pass == 1) {
		goto skip_avtab_rule;
	}

	switch(rule_type) {
	case RULE_TE_ALLOW:
		if(!(parse_policy->opts & POLOPT_TE_ALLOW))
			goto skip_avtab_rule;
		rt = add_avrule(rule_type, &(parse_policy->av_access), &(parse_policy->num_av_access), TRUE);
		break;
	case RULE_NEVERALLOW:
		if(!(parse_policy->opts & POLOPT_TE_NEVERALLOW))
			goto skip_avtab_rule;
		rt = add_avrule(rule_type, &(parse_policy->av_access), &(parse_policy->num_av_access), TRUE);
		break;
	
	/* Jul 2002, added RULE_DONTAUDIT, which replaces RULE_NOTIFY */
	case RULE_DONTAUDIT:
		rt = set_policy_version(POL_VER_JUL2002, parse_policy);
		if(rt != 0) {
			yyerror("error setting policy version");
			return -1;
		}
		/* fall thru */
	case RULE_AUDITDENY:
		if(!(parse_policy->opts & POLOPT_TE_DONTAUDIT))
			goto skip_avtab_rule;
		rt = add_avrule(rule_type, &(parse_policy->av_audit), &(parse_policy->num_av_audit), TRUE);
		break;
	case RULE_AUDITALLOW:
		if(!(parse_policy->opts & POLOPT_TE_AUDITALLOW))
			goto skip_avtab_rule;
		rt = add_avrule(rule_type, &(parse_policy->av_audit), &(parse_policy->num_av_audit), TRUE);
		break;
	
	default:
		sprintf(errormsg, "Invalid AV type (%d)", rule_type);
		yyerror(errormsg);
		return -1;
	}
	if(rt < 0) 
		return rt;
	(parse_policy->rule_cnt[rule_type])++;
	return 0;
skip_avtab_rule:
	while ((id = queue_remove(id_queue))) 
		free(id);
	while ((id = queue_remove(id_queue))) 
		free(id);
	while ((id = queue_remove(id_queue))) 
		free(id);
	while ((id = queue_remove(id_queue))) 
		free(id);
	return 0;
}	

/* add a new type transition rule */
static int add_ttrule(int rule_type, bool_t enabled)
{
	int idx, idx_type;
	char *id;
	tt_item_t *item;
	ta_item_t *titem;
	bool_t subtract;
		
	if (parse_policy->num_te_trans >= (parse_policy->list_sz[POL_LIST_TE_TRANS])) {
		/* grow the dynamic array */
		tt_item_t *ptr;		
		ptr = (tt_item_t *)realloc(parse_policy->te_trans, (LIST_SZ + parse_policy->list_sz[POL_LIST_TE_TRANS]) * sizeof(tt_item_t));
		if(ptr == NULL) {
			yyerror("out of memory\n");
			return -1;
		}
		parse_policy->te_trans = ptr;
		parse_policy->list_sz[POL_LIST_TE_TRANS] += LIST_SZ;
	}	
	
	item = &(parse_policy->te_trans[parse_policy->num_te_trans]);
	memset(item, 0, sizeof(tt_item_t));
	item->type = rule_type;
	item->lineno = policydb_lineno;
	item->enabled = enabled;

	/* source (domain) types/attribs */
	subtract = FALSE;
	while ((id = queue_remove(id_queue))) {
		if(strcmp(id, "*") == 0) {
			item->flags |= AVFLAG_SRC_STAR;
			free(id);
			continue;
		}
		if (strcmp(id, "-") == 0) {
			subtract = TRUE;
			free(id);
			continue;
		}
		if(strcmp(id, "~") == 0) {
			item->flags |= AVFLAG_SRC_TILDA;
			free(id);
			continue;
		}
		idx = get_type_or_attrib_idx(id, &idx_type, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "%s is neither a type or type attribute", id);
			yyerror(errormsg);
			return -1;				
		}
		titem = (ta_item_t *)malloc(sizeof(ta_item_t));
		if(titem == NULL) {
			yyerror("out of memory");
			return -1;
		}
		titem->type = idx_type;
		if (subtract) {
			titem->type |= IDX_SUBTRACT;
			subtract = FALSE;
		}
		titem->idx = idx;
		if(insert_ta_item(titem, &(item->src_types)) != 0) {
			sprintf(errormsg, "failed ta_item insetion for source type id %s\n", id);
			yyerror(errormsg);
			return -1;
		}
		free(id);
	}
	
	/* target object types/attribs */
	subtract = FALSE;
	while ((id = queue_remove(id_queue))) {
		if(strcmp(id, "*") == 0) {
			item->flags |= AVFLAG_TGT_STAR;
			free(id);
			continue;
		}
		if(strcmp(id, "~") == 0) {
			item->flags |= AVFLAG_TGT_TILDA;
			free(id);
			continue;
		}
		if (strcmp(id, "-") == 0) {
			subtract = TRUE;
			free(id);
			continue;
		}
		idx = get_type_or_attrib_idx(id, &idx_type, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "%s is neither a type or type attribute", id);
			yyerror(errormsg);
			return -1;				
		}
		titem = (ta_item_t *)malloc(sizeof(ta_item_t));
		if(titem == NULL) {
			yyerror("out of memory");
			return -1;
		}
		titem->type = idx_type;
		if (subtract) {
			titem->type |= IDX_SUBTRACT;
			subtract = FALSE;
		}
		titem->idx = idx;
		if(insert_ta_item(titem, &(item->tgt_types)) != 0) {
			sprintf(errormsg, "failed ta_item insetion for target type id %s\n", id);
			yyerror(errormsg);
			return -1;
		}
		free(id);
	}		
	
	/* object classes */
	while ((id = queue_remove(id_queue))) {
		if(strcmp(id, "*") == 0) {
			item->flags |= AVFLAG_CLS_STAR;
			free(id);
			continue;
		}
		if(strcmp(id, "~") == 0) {
			item->flags |= AVFLAG_CLS_TILDA;
			free(id);
			continue;
		}
		idx = get_obj_class_idx(id, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "%s is not a valid object class name", id);
			yyerror(errormsg);
			return -1;
		}
		titem = (ta_item_t *)malloc(sizeof(ta_item_t));
		if(titem == NULL) {
			yyerror("out of memory");
			return -1;
		}
		titem->type = IDX_OBJ_CLASS;
		titem->idx = idx;
		if(insert_ta_item(titem, &(item->classes)) != 0) {
			sprintf(errormsg, "failed ta_item insetion for classes id %s", id);
			yyerror(errormsg);
			return -1;
		}
		free(id);
	}
	
	/* default type */	
	id = queue_remove(id_queue);
	idx = get_type_or_attrib_idx(id, &idx_type, parse_policy);
	if(idx < 0 || idx_type != IDX_TYPE) {
		sprintf(errormsg, "default type %s is NOT a defined type.", id);
		yyerror(errormsg);
		return -1;				
	}
	item->dflt_type.type = idx_type;
	item->dflt_type.idx = idx;
	free(id);	

	(parse_policy->num_te_trans)++;
	return parse_policy->num_te_trans - 1;
}


/* put type transition (change, member) rules in policy object */
static int define_compute_type(int rule_type)
{
	char *id;
	int rt;
	
	if (pass == 1) {
		goto skip_tt_rule;
	}

	switch(rule_type) {
	case RULE_TE_TRANS:
		if(!(parse_policy->opts & POLOPT_TE_TRANS))
			goto skip_tt_rule;
		break;	
	case RULE_TE_MEMBER:
		if(!(parse_policy->opts & POLOPT_TE_MEMBER))
			goto skip_tt_rule;
		break;
	case RULE_TE_CHANGE:
		if(!(parse_policy->opts & POLOPT_TE_CHANGE))
			goto skip_tt_rule;
		break;
	default:
		sprintf(errormsg, "Invalid type transition|member|change rule type (%d)", rule_type);
		yyerror(errormsg);
		return -1;
	}
	rt = add_ttrule(rule_type, TRUE);
	if(rt < 0) 
		return rt;
		
	(parse_policy->rule_cnt[rule_type])++;
	return 0;
	
skip_tt_rule:
	while ((id = queue_remove(id_queue))) 
		free(id);
	while ((id = queue_remove(id_queue))) 
		free(id);
	while ((id = queue_remove(id_queue))) 
		free(id);
	id = queue_remove(id_queue);
	free(id);
	return 0;	
}

/* capture clone rule; we won't actually clone rules but keep the actual CLONE statements 
 * and resolve clones when needed */
/* pre Jul 2002 only */
static int define_te_clone(void)
{
	char *id;
	int  src, tgt, rt;

	if (pass == 1) {
		id = queue_remove(id_queue);
		free(id);
		id = queue_remove(id_queue);
		free(id);
		return 0;
	}
	id = queue_remove(id_queue);
	src = get_type_idx(id, parse_policy);
	if(src < 0) {
		sprintf(errormsg, "Invalid source type (%s)", id);
		yyerror(errormsg);
		return -1;
	}
	free(id);
	
	id = queue_remove(id_queue);
	tgt = get_type_idx(id, parse_policy);
	if(tgt < 0) {
		sprintf(errormsg, "Invalid target type (%s)", id);
		yyerror(errormsg);
		return -1;
	}
	free(id);	
	
	rt = add_clone_rule(src, tgt, policydb_lineno, parse_policy);
	if(rt != 0) return rt;
	
	(parse_policy->rule_cnt[RULE_CLONE])++;

	rt= set_policy_version(POL_VER_PREJUL2002, parse_policy);
	if (rt != 0) {
		yyerror("error setting policy version");
		return -1;
	}
	return 0;	
}


static int define_role_types(void)
{
	char *id, *or_name;
	int i, role_idx, idx, idx_type, num_types, *types, rt;

	if (pass == 1 || (pass == 2 && !(parse_policy->opts & POLOPT_ROLES))) {
		while ((id = queue_remove(id_queue))) 
			free(id);
		return 0;
	}

	id = (char *) queue_remove(id_queue);
	if (!id) {
		yyerror("no role name for role definition?");
		return -1;
	}
	if(!is_valid_str_sz(id) ) {
		sprintf(errormsg, "string \"%s\" is too large", id);
		yyerror(errormsg);
		return -1;
	}
	
	/* If this is the first role to be added, then add the hard-coded
	 * default object role "object_r" as it will not show up in the policy */
	if(parse_policy->num_roles < 1) {
		#define OR_NAME "object_r"
		or_name = (char *)malloc(strlen(OR_NAME) + 1);
		strcpy(or_name, OR_NAME);
		role_idx = add_role(or_name, parse_policy);
		if(role_idx < 0) {
			yyerror("Problem adding object role object_r to policy");
			free(id);
			return -1;
		}
		assert(role_idx == 0);
	}
	
	/* if the role already exists, we'll just add the new type, otherwise
	 * we create new role */
	role_idx = get_role_idx(id, parse_policy);
	if(role_idx < 0) {
		role_idx = add_role(id, parse_policy);
		/* don't free id if we added it; the add_role type uses the memory */
		if(role_idx < 0) {
			sprintf(errormsg, "Problem adding role %s to policy", id);
			yyerror(errormsg);
			free(id);
			return -1;
		}
	}
	else {
		/* get rid of the role name if it alrady exists */
		free(id);
	}
	/* add the types or attributes */	
	while ((id = queue_remove(id_queue))) {
		idx = get_type_or_attrib_idx(id, &idx_type, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "Invalid type name (%s) in role definition", id);
			yyerror(errormsg);
			return -1;
		}
		if (idx_type == IDX_TYPE) {
			rt = add_type_to_role(idx, role_idx, parse_policy);
			if(rt != 0)
				return rt;
		} else {
			rt = get_attrib_types(idx, &num_types, &types, parse_policy);
			if (rt != 0)
				return rt;
			for (i = 0; i < num_types; i++) {
				rt = add_type_to_role(types[i], role_idx, parse_policy);
				if(rt != 0) { 
					free(types);
					return rt;
				}
				
			}
			free(types);
		}
		free(id);	
	}

	return 0;
}


static int define_role_allow(void)
{
	char *id;
	int idx;
	ta_item_t *role = NULL;
	role_allow_t *rule = NULL;
	
	if(pass == 1 || (pass == 2 && !(parse_policy-> opts & POLOPT_ROLE_RULES))) {
		while ((id = queue_remove(id_queue))) 
			free(id);
		while ((id = queue_remove(id_queue))) 
			free(id);
		return 0;
	}
	
	if(parse_policy->num_role_allow >= parse_policy->list_sz[POL_LIST_ROLE_ALLOW]) {
		/* grow the dynamic array */
		role_allow_t * ptr;		
		ptr = (role_allow_t *)realloc(parse_policy->role_allow, (LIST_SZ+parse_policy->list_sz[POL_LIST_ROLE_ALLOW]) * sizeof(role_allow_t));
		if(ptr == NULL) {
			yyerror("out of memory\n");
			return -1;
		}
		parse_policy->role_allow = ptr;
		parse_policy->list_sz[POL_LIST_ROLE_ALLOW] += LIST_SZ;
	}	
	rule = &(parse_policy->role_allow[parse_policy->num_role_allow]);
	memset(rule, 0, sizeof(role_allow_t));
	rule->lineno = policydb_lineno;
	
	/* source roles*/
	while ((id = queue_remove(id_queue))) {
		if(strcmp(id, "*") == 0) {
			rule->flags |= AVFLAG_SRC_STAR;
			free(id);
			continue;
		}
		if(strcmp(id, "~") == 0) {
			rule->flags |= AVFLAG_SRC_TILDA;
			free(id);
			continue;
		}
		idx = get_role_idx(id, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "%s is an invalid role attribute", id);
			yyerror(errormsg);
			free(id);
			return -1;				
		}
		role = (ta_item_t *)malloc(sizeof(ta_item_t));
		if(role == NULL) {
			yyerror("out of memory");
			free(id);
			return -1;
		}
		role->type = IDX_ROLE;
		role->idx = idx;
		if(insert_ta_item(role, &(rule->src_roles)) != 0) {
			sprintf(errormsg, "failed ta_item insetion for source rule id %s\n", id);
			yyerror(errormsg);
			free(id);
			free(role);
			return -1;
		}
		free(id);
	}
	
	/* target object types/attribs */
	while ((id = queue_remove(id_queue))) {
		if(strcmp(id, "*") == 0) {
			rule->flags |= AVFLAG_TGT_STAR;
			free(id);
			free(role);
			continue;
		}
		if(strcmp(id, "~") == 0) {
			rule->flags |= AVFLAG_TGT_TILDA;
			free(id);
			continue;
		}	
		idx = get_role_idx(id, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "%s is not a valid role", id);
			yyerror(errormsg);
			free(id);
			return -1;				
		}
		role = (ta_item_t *)malloc(sizeof(ta_item_t));
		if(role == NULL) {
			yyerror("out of memory");
			free(id);
			return -1;
		}
		role->type = IDX_ROLE;
		role->idx = idx;
		if(insert_ta_item(role, &(rule->tgt_roles)) != 0) {
			sprintf(errormsg, "failed ta_item insetion for target role id %s\n", id);
			yyerror(errormsg);
			free(id);
			free(role);
			return -1;
		}
		free(id);
	}
	
	(parse_policy->num_role_allow)++;	
	(parse_policy->rule_cnt[RULE_ROLE_ALLOW])++;		
	return 0;
}


static int define_role_trans(void)
{
	char *id;
	int idx, idx_type;
	rt_item_t *rule;
	ta_item_t *role = NULL, *type = NULL;
	
	if(pass == 1 || (pass == 2 && !(parse_policy-> opts & POLOPT_ROLE_RULES))) {
		while ((id = queue_remove(id_queue))) 
			free(id);			/* src roles */
		while ((id = queue_remove(id_queue))) 
			free(id);			/* tgt types */
		id = queue_remove(id_queue);
		free(id);				/* trans. role */
		return 0;
	}

	if(parse_policy->num_role_trans >= parse_policy->list_sz[POL_LIST_ROLE_TRANS]) {
		/* grow the dynamic array */
		rt_item_t *ptr;		
		ptr = (rt_item_t *)realloc(parse_policy->role_trans, 
			(LIST_SZ+parse_policy->list_sz[POL_LIST_ROLE_TRANS]) * sizeof(rt_item_t));
		if(ptr == NULL) {
			yyerror("out of memory\n");
			return -1;
		}
		parse_policy->role_trans = ptr;
		parse_policy->list_sz[POL_LIST_ROLE_TRANS] += LIST_SZ;
	}	
	rule = &(parse_policy->role_trans[parse_policy->num_role_trans]);
	memset(rule, 0, sizeof(rt_item_t));	
	rule->lineno = policydb_lineno;
	
	/* source ROLES*/
	while ((id = queue_remove(id_queue))) {
		if(strcmp(id, "*") == 0) {
			rule->flags |= AVFLAG_SRC_STAR;
			free(id);
			continue;
		}
		if(strcmp(id, "~") == 0) {
			rule->flags |= AVFLAG_SRC_TILDA;
			free(id);
			continue;
		}
		idx = get_role_idx(id, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "%s is an invalid role name", id);
			yyerror(errormsg);
			free(id);
			return -1;				
		}
		role = (ta_item_t *)malloc(sizeof(ta_item_t));
		if(role == NULL) {
			yyerror("out of memory");
			free(id);
			return -1;
		}
		role->type = IDX_ROLE;
		role->idx = idx;
		if(insert_ta_item(role, &(rule->src_roles)) != 0) {
			sprintf(errormsg, "failed ta_item insetion for source rule id %s\n", id);
			yyerror(errormsg);
			free(role);
			free(id);
			return -1;
		}
		free(id);
	}
	
	/* target TYPES/ATTRIBS */
	while ((id = queue_remove(id_queue))) {
		if(strcmp(id, "*") == 0) {
			rule->flags |= AVFLAG_TGT_STAR;
			free(id);
			continue;
		}
		if(strcmp(id, "~") == 0) {
			rule->flags |= AVFLAG_TGT_TILDA;
			free(id);
			continue;
		}
		idx = get_type_or_attrib_idx(id, &idx_type, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "%s is neither a type or type attribute", id);
			yyerror(errormsg);
			free(id);
			free(role);
			return -1;				
		}
		type = (ta_item_t *)malloc(sizeof(ta_item_t));
		if(type == NULL) {
			yyerror("out of memory");
			free(id);
			free(role);
			return -1;
		}
		type->type = idx_type;
		type->idx = idx;
		if(insert_ta_item(type, &(rule->tgt_types)) != 0) {
			sprintf(errormsg, "failed ta_item insetion for target type %s\n", id);
			yyerror(errormsg);
			free(id);
			free(role);
			free(type);
			return -1;
		}
		free(id);
	}	
	
	/* transition role */
	id = queue_remove(id_queue);
	rule->trans_role.idx = get_role_idx(id, parse_policy);
	rule->trans_role.type = IDX_ROLE;
	if(rule->trans_role.idx < 0) {
		sprintf(errormsg, "%s is an invalid role name", id);
		yyerror(errormsg);
		free(role);
		free(type);
		free(id);
		return -1;				
	}
	free(id);	
	(parse_policy->num_role_trans)++;	
	(parse_policy->rule_cnt[RULE_ROLE_TRANS])++;			
	return 0;
}


/* users list */

static int define_user(void)
{
	char *id;
	int idx, rt;
	user_item_t *ptr;
	bool_t existing;
	if(pass == 1 || (pass == 2 && !(parse_policy-> opts & POLOPT_USERS))) {
		while ((id = queue_remove(id_queue))) 
			free(id);
		return 0;
	}
	
	id = (char *) queue_remove(id_queue);
	if (!id) {
		yyerror("no user name for user definition?");
		return -1;
	}
	if(!is_valid_str_sz(id)) {
		sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
		yyerror(errormsg);
		return -1;
	}
	/* check if existing user; if so treat as union of roles */
	if(get_user_by_name(id, &ptr, parse_policy) == 0) {
		/* existing; ptr now points to existing user record */
		existing = TRUE;
		free(id);
	}
	else {
		/* new user */
		existing = FALSE;
		ptr = (user_item_t *)malloc(sizeof(user_item_t));
		if(ptr == NULL) {
			yyerror("out of memory");
			return -1;
		}
		memset(ptr, 0, sizeof(user_item_t));
		ptr->name = id;
	}
		
	while((id = queue_remove(id_queue))) {
		ta_item_t *newitem;
		idx = get_role_idx(id, parse_policy);
		if(idx < 0) {
			sprintf(errormsg, "%s is an invalid role name", id);
			yyerror(errormsg);
			free(id);
			return -1;
		}
		if(!existing || (existing && !does_user_have_role(ptr, idx, parse_policy))) {
			newitem = (ta_item_t *)malloc(sizeof(ta_item_t));
			if(newitem == NULL) {
				yyerror("out of memory");
				free(id);
				return -1;
			}
			newitem->idx = idx;
			newitem->type = IDX_ROLE;
			rt = insert_ta_item(newitem, &(ptr->roles));
			if(rt != 0) {
				yyerror("problem inserting role in user");
				return -1;
			}
		}
		free(id);		 
	}
	
	if(!existing) {
		rt = append_user(ptr, &(parse_policy->users));
		if(rt != 0) {
			yyerror("problem inserting user in policy ");
			return -1;
		}		
		(parse_policy->rule_cnt[RULE_USER])++;
	}
	return 0;
}

/* class definitions */

static int define_class(void)
{
	char *id = 0;
	int idx;
	
	if(pass == 2 || (pass == 1 && !(parse_policy->opts & POLOPT_CLASSES))) {
		id = queue_remove(id_queue);
		free(id);
		return 0;
	}
	
	/* add class name */
	id = queue_remove(id_queue);
	if(!id) {
		yyerror("no class name for class definitions\n");
		return -1;
	}
	if(!is_valid_str_sz(id)) {
		sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
		yyerror(errormsg);
		return -1;
	}
	idx = add_class(id, parse_policy);
	if(idx == -2) {
		sprintf(errormsg, "duplicate class decalaration (%s)\n", id);
		yyerror(errormsg);
		return -1;
	}
	else if(idx < 0) 
		return -1;
	
	return 0;
}

/* object permissions permissions */
static int define_av_perms(int inherits)
{
	char *id;
	int cls_idx, cp_idx, p_idx, rt;
	char *tname = NULL;
	if(pass == 2 || (pass == 1 && !(parse_policy->opts & POLOPT_CLASSES)) || 
		(pass == 1 && !(parse_policy->opts & POLOPT_PERMS))) {
		while ((id = queue_remove(id_queue))) 
			free(id);
		return 0;
	}
	id = queue_remove(id_queue);
	if(!id) {
		yyerror("no class name for permission definition");
		return -1;
	}
	cls_idx = get_obj_class_idx(id, parse_policy);
	if(cls_idx < 0) {
		sprintf(errormsg, "%s is not a valid object class name", id);
		yyerror(errormsg);
		return -1;
	}
	free(id);
	if (inherits) {
		id = (char *) queue_remove(id_queue);
		if (!id) {
			yyerror("no inherits name for access vector definition?");
			return -1;
		}
		cp_idx = get_common_perm_idx(id, parse_policy);
		if(cp_idx < 0) {
			sprintf(errormsg, "%s is not a valid object class name", id);
			yyerror(errormsg);
			return -1;
		}
		tname = id; /* temporarily keep around for check below */
		rt = add_common_perm_to_class(cls_idx, cp_idx, parse_policy);
		if( rt <  0) {
			yyerror("problem adding common perm idx to class");
			return -1;
		}		
	} 
	/* class-specific permissions */
	while ((id = queue_remove(id_queue))) {
		p_idx = add_perm(id, parse_policy);
		if(p_idx < 0) {
			sprintf(errormsg, "problem adding permisions %s", id);
			yyerror(errormsg);
			return -1;
		}
		/* this check straight from checkpolicy; not sure necessary ??? */
		if (inherits) {
			/*
			 * Class-specific permissions and 
			 * common permissions exist in the same
			 * name space.
			 */
			
			if(strcasecmp(id, tname) == 0) {
				sprintf(errormsg, "class-specific permission (%s) conflicts with common permission", id);
				yyerror(errormsg);
				return -1;
			}
		}
		if(!is_valid_str_sz(id)) {
			sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
			yyerror(errormsg);
			return -1;
		}
		rt = add_perm_to_class(cls_idx, p_idx, parse_policy);
		if(rt != 0) {
			sprintf(errormsg, "problem adding permission (%s) to object class", id);
			yyerror(errormsg);
			return -1;
		}
		free(id);		
	}
	if(inherits) 
		free(tname); /* no longer need common name */
	
	
	return 0;
}


/* common permissions */
static int define_common_perms(void)
{
	char *id = 0;
	int idx, permidx, rt;
	
	if (pass == 2 || (pass == 1 && !(parse_policy->opts & POLOPT_PERMS))) {
		while ((id = queue_remove(id_queue))) 
			free(id);
		return 0;
	}
	
	id = (char *) queue_remove(id_queue);
	if (!id) {
		yyerror("no common name for common perm definition?");
		return -1;
	}
	
	/* add new common perm */
	if(!is_valid_str_sz(id)) {
		sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
		yyerror(errormsg);
		return -1;
	}
	idx = add_common_perm(id, parse_policy);
	if(idx == -2) {
		sprintf(errormsg, "Duplicate common permission name (%s)", id);
		yyerror(errormsg);
		return -1;
	}
	else if(idx < 0)
		return -1; /* other err */
	
	/* add permissions to common perm */
	while ((id = queue_remove(id_queue))) {	
		if(!is_valid_str_sz(id)) {
			sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
			yyerror(errormsg);
			return -1;
		}
		permidx = add_perm(id, parse_policy);
		if(permidx < 0) {
			free(id); /* add_perm() allocates its own memory */
			sprintf(errormsg, "Problem adding permission name (%s)", id);
			yyerror(errormsg);
			return -1;
		}
		free(id); /* add_perm() allocates its own memory */
		rt = add_perm_to_common(idx, permidx, parse_policy);
		/* Note: a -2 return (already exists) is fine here */
		if(rt == -1 ) {
			yyerror("Problem adding permission idx to common permission");
			return -1;
		}
	}
	return 0;
}

/* TODO: Temporary fix to allow role names defined by role domainance to exist
 * in policy name space.  Still need to handle their definitions.
 */
 
static int
 define_role_dom(void)
{
	char *id;
	int idx;
	role_item_t *role;
	
	id = queue_remove(id_queue);
	if (!id) {
		yyerror("no role name for role dominance?");
		return -1;
	}
	if (pass == 1 || (pass == 2 && !(parse_policy->opts & POLOPT_ROLES))) {
		free(id);
		return 1;
	}
	
	/* pass 2 */
	/* if the role already exists, we'll just add the new type, otherwise
	 * we create new role */
	idx = get_role_idx(id, parse_policy);
	if(idx < 0) {
		/* new role identifier; for now just create the role...nothing
		 * else will be done with it but user statements can use it!
		 * TODO: Finish this!
		 */
		if(!is_valid_str_sz(id) ) {
			sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
			yyerror(errormsg);
			return -1;
		}
		/* Make sure role array is large enough */
		if(parse_policy->num_roles >= parse_policy->list_sz[POL_LIST_ROLES]) {
			/* grow the dynamic array */
			role_item_t * ptr;		
				ptr = (role_item_t *)realloc(parse_policy->roles, (LIST_SZ+parse_policy->list_sz[POL_LIST_ROLES]) * sizeof(role_item_t));
			if(ptr == NULL) {
				yyerror("out of memory\n");
				return -1;
			}
			parse_policy->roles = ptr;
			parse_policy->list_sz[POL_LIST_ROLES] += LIST_SZ;
		}
		/* take next available as new role */
		role = &(parse_policy->roles[parse_policy->num_roles]);
		role->name = id;	/* don't free id if new */
		role->num_types = 0;
		role->types = NULL;
		(parse_policy->num_roles)++;
	}
	else {
		/* already exists; we're done for now
		 * TODO: handle dominance semantics
		 */
		free(id);
	}
		
	return 1; 
}


static int define_bool(void)
{
	char *id, *name;
	bool_t val;
	int rt;
	
	rt = set_policy_version(POL_VER_COND, parse_policy);
	if(rt != 0) {
		yyerror("error setting policy version");
		return -1;
	}
	
	if (!(parse_policy->opts & POLOPT_COND_BOOLS) || pass == 2) {
		while ((id = (char*)queue_remove(id_queue)))
			free(id);
		return 0;
	}
	
	name = (char*)queue_remove(id_queue);
	if (!name) {
		yyerror("No name for boolean declaration");
		return -1;
	}
	
	id = (char*)queue_remove(id_queue);
	if (!id) {
		yyerror("No value for boolean declaration");
		return -1;
	}
	
	if (strcmp(id, "T") == 0)
		val = TRUE;
	else
		val = FALSE;
	free(id);
	
	rt = add_cond_bool(name, val, parse_policy);
	if (rt == -2) {
		sprintf(errormsg, "Boolean %s already exists", name);
		yyerror(errormsg);
		return -1;
	} else if (rt < 0) {
		yyerror("Error adding boolean");
		return -1;
	}
	
	return 0;
}

/* search through the policy for a matching conditional expression
 * returns -1 if non or found
 * returns the index of the cond_expr_item_t if found.
 */
static int find_matching_cond_expr(cond_expr_t *expr, policy_t *policy)
{
	int i;
	
	for (i = 0; i < policy->num_cond_exprs; i++) {
		if (cond_exprs_equal(expr, policy->cond_exprs[i].expr))
			return i;
	}
	return -1;
}

static int cond_rule_add_helper(int **list, int *list_len, int *add, int add_len)
{
	int i;
	
	if (!add)
		return 0;
		
	if (!*list) {
		*list = add;
		return 0;
	}
	
	for (i = 0; i < add_len; i++) {
		/* we probably don't need to do this checking, but it is better to be safe */
		if (find_int_in_array(add[i], *list, *list_len) == -1) {
			if (add_i_to_a(add[i], list_len, list) == -1)
				return -1;
		}
	}

	return 0;
}

static int define_conditional(cond_expr_t *expr, cond_rule_list_t *t_list, cond_rule_list_t *f_list)
{
	int idx, rt;
	cond_expr_item_t *cur = NULL;
	
	rt = set_policy_version(POL_VER_COND, parse_policy);
	if(rt != 0) {
		yyerror("error setting policy version");
		return -1;
	}
	
	if (pass == 1)
		return 0;
	
	if (expr == &dummy_cond_expr) {
		yyerror("Received invalid expression in define_conditional");
		return -1;
	}
	
	idx = find_matching_cond_expr(expr, parse_policy);
	
	/* found matching expressions - add the rules to this expression. */
	if (idx != -1) {
		cond_free_expr(expr);
		cur = &parse_policy->cond_exprs[idx];
		if (t_list) {
			if (!cur->true_list) {
				cur->true_list = t_list;
			} else {
				if (cond_rule_add_helper(&cur->true_list->av_access, &cur->true_list->num_av_access,
					t_list->av_access, t_list->num_av_access) == -1)
						return -1;
				if (cond_rule_add_helper(&cur->true_list->av_audit, &cur->true_list->num_av_audit,
					t_list->av_audit, t_list->num_av_audit) == -1)
						return -1;
				if (cond_rule_add_helper(&cur->true_list->te_trans, &cur->true_list->num_te_trans,
					t_list->te_trans, t_list->num_te_trans) == -1)
						return -1;
				cond_free_rules_list(t_list);
			}
				
		}
		if (f_list) {
			if (!cur->false_list) {
				cur->false_list = f_list;
			} else {
				if (cond_rule_add_helper(&cur->false_list->av_access, &cur->false_list->num_av_access,
					f_list->av_access, f_list->num_av_access) == -1)
						return -1;
				if (cond_rule_add_helper(&cur->false_list->av_audit, &cur->false_list->num_av_audit,
					f_list->av_audit, f_list->num_av_audit) == -1)
						return -1;
				if (cond_rule_add_helper(&cur->false_list->te_trans, &cur->false_list->num_te_trans,
					f_list->te_trans, f_list->num_te_trans) == -1)
						return -1;
				cond_free_rules_list(f_list);
			}
				
		}
	} else {
		if (add_cond_expr_item(expr, t_list, f_list, parse_policy) < 0) {
			yyerror("Error adding conditional expression item to the policy");
			return -1;
		}
	}
	
	if (update_cond_expr_items(parse_policy) != 0)
		return -1;
        
	return 0;
}

static cond_expr_t *define_cond_expr(__u32 expr_type, void *arg1, void *arg2)
{
	char *id;
	cond_expr_t *expr, *e1 = NULL, *e2;
	int bool_var;
	
	if (pass == 1) {
		if (expr_type == COND_BOOL) {
			while ((id = queue_remove(id_queue)))
				free(id);
		}
		return &dummy_cond_expr;
	}
	
	if (!(parse_policy->opts & POLOPT_COND_BOOLS)) {
		return &dummy_cond_expr;
	}
	
	/* create a new expression struct */
	expr = malloc(sizeof(struct cond_expr));
	if (!expr) {
		yyerror("out of memory");
		return NULL;
	}
	memset(expr, 0, sizeof(cond_expr_t));
	expr->expr_type = expr_type;
	
	/* create the type asked for */
	switch (expr_type) {
	case COND_NOT:
		e1 = NULL;
		e2 = (struct cond_expr *) arg1;
		while (e2) {
			e1 = e2;
			e2 = e2->next;
		}
		if (!e1 || e1->next) {
			yyerror("illegal conditional NOT expression");
			free(expr);
			return NULL;
		}
		e1->next = expr;
		return (struct cond_expr *) arg1;
	case COND_AND:
	case COND_OR:
	case COND_XOR:
	case COND_EQ:
	case COND_NEQ:
		e1 = NULL;
		e2 = (struct cond_expr *) arg1;
		while (e2) {
			e1 = e2;
			e2 = e2->next;
		}
		if (!e1 || e1->next) {
			yyerror("illegal left side of conditional binary op expression");
			free(expr);
			return NULL;
		}
		e1->next = (struct cond_expr *) arg2;

		e1 = NULL;
		e2 = (struct cond_expr *) arg2;
		while (e2) {
			e1 = e2;
			e2 = e2->next;
		}
		if (!e1 || e1->next) {
			yyerror("illegal right side of conditional binary op expression");
			free(expr);
			return NULL ;
		}
		e1->next = expr;
		return (struct cond_expr *) arg1;
	case COND_BOOL:
		id = (char *) queue_remove(id_queue) ;
		if (!id) {
			yyerror("bad conditional; expected boolean id");
			free(id);
			free(expr);
			return NULL;
		}
		
		bool_var = get_cond_bool_idx(id, parse_policy);
		
		if (bool_var < 0) {
			sprintf(errormsg, "unknown boolean %s in conditional expression", id);
			yyerror(errormsg);
			free(expr);
			free(id);
			return NULL ;
		}
		expr->bool = bool_var;
                free(id);
		return expr;
	default:
		yyerror("illegal conditional expression");
		return NULL;
	}
}

/* collect the type lists */
static cond_rule_list_t *define_cond_pol_list(cond_rule_list_t *list, rule_desc_t *rule)
{
	cond_rule_list_t *rl;
	
	if (pass == 1)
		return (cond_rule_list_t*)1;
		
	if (!list) {
		rl = (cond_rule_list_t*)malloc(sizeof(cond_rule_list_t));
		if (!rl) {
			yyerror("Memory error");
			free(rule);
			return NULL;
		}
		memset(rl, 0, sizeof(cond_rule_list_t));
	} else {
		rl = list;
	}
	
	if (!rule || rule == &dummy_rule_desc)
		return rl;
	
	switch (rule->rule_type) {
	case RULE_TE_ALLOW:
	case RULE_NEVERALLOW:
		if (add_i_to_a(rule->idx, &rl->num_av_access, &rl->av_access) != 0) {
			yyerror("Memory error");
			free(rule);
			return NULL;
		}
		break;
	case RULE_DONTAUDIT:
	case RULE_AUDITDENY:
	case RULE_AUDITALLOW:
		if (add_i_to_a(rule->idx, &rl->num_av_audit, &rl->av_audit) != 0) {
			yyerror("Memory error");
			free(rule);
			return NULL;
		}
		break;
	case RULE_TE_TRANS:
	case RULE_TE_MEMBER:
	case RULE_TE_CHANGE:
		if (add_i_to_a(rule->idx, &rl->num_te_trans, &rl->te_trans) != 0) {
			yyerror("Memory error");
			free(rule);
			return NULL;
		}
		break;
	default:
		yyerror("Internal error: invalid type description.");
		free(rule);
		return NULL;
	}
	
	free(rule);
	return rl;
}

static rule_desc_t *define_cond_compute_type(int rule_type)
{
	char *id;
	int rt;
	rule_desc_t *rule;
	
	if (pass == 1)
		goto skip_tt_rule;
		
	if (!(parse_policy->opts & POLOPT_COND_TE_RULES))
		goto skip_tt_rule;
				
	rule = (rule_desc_t*)malloc(sizeof(rule_desc_t));
	if (!rule) {
		yyerror("Memory error");
		return NULL;
	}
	memset(rule, 0, sizeof(rule_desc_t));
	
	switch(rule_type) {
	case RULE_TE_TRANS:
	case RULE_TE_MEMBER:
	case RULE_TE_CHANGE:
		break;
	default:
		sprintf(errormsg, "Invalid type transition|member|change rule type (%d)", rule_type);
		yyerror(errormsg);
		return NULL;
	}
	rt = add_ttrule(rule_type, TRUE);
	if(rt != 0) 
		return NULL;
		
	(parse_policy->rule_cnt[rule_type])++;
	
	rule->rule_type = rule_type;
	rule->idx = rt;
		
	return rule;
	
skip_tt_rule:
	/* TODO: Currently an empty stub */	
	while ((id = queue_remove(id_queue))) 
		free(id);
	while ((id = queue_remove(id_queue))) 
		free(id);
	while ((id = queue_remove(id_queue))) 
		free(id);
	id = queue_remove(id_queue);
	free(id);
	return &dummy_rule_desc;
}

static rule_desc_t *define_cond_te_avtab(int rule_type)
{
	char *id;
        int rt;
	rule_desc_t *rule;
	        
	if (pass == 1) {
		goto skip_avtab_rule;
	}
	
	if(!(parse_policy->opts & POLOPT_COND_TE_RULES))
                goto skip_avtab_rule;	
	
	rule = (rule_desc_t*)malloc(sizeof(rule_desc_t));
	if (!rule) {
		yyerror("Memory error");
		return NULL;
	}
	memset(rule, 0, sizeof(rule_desc_t));
	
	switch(rule_type) {
	case RULE_TE_ALLOW:
		rt = add_avrule(rule_type, &(parse_policy->av_access), &(parse_policy->num_av_access), TRUE);
		break;
	case RULE_NEVERALLOW:
		rt = add_avrule(rule_type, &(parse_policy->av_access), &(parse_policy->num_av_access), TRUE);
		break;
	
	/* Jul 2002, added RULE_DONTAUDIT, which replaces RULE_NOTIFY */
	case RULE_DONTAUDIT:
		rt = set_policy_version(POL_VER_JUL2002, parse_policy);
		if(rt != 0) {
			yyerror("error setting policy version");
			return NULL;
		}
		/* fall thru */
	case RULE_AUDITDENY:
		rt = add_avrule(rule_type, &(parse_policy->av_audit), &(parse_policy->num_av_audit), TRUE);
		break;
	case RULE_AUDITALLOW:
		rt = add_avrule(rule_type, &(parse_policy->av_audit), &(parse_policy->num_av_audit), TRUE);
		break;
	default:
		sprintf(errormsg, "Invalid AV type (%d)", rule_type);
		yyerror(errormsg);
		return NULL;
	}
	if (rt < 0) 
		return NULL;
	(parse_policy->rule_cnt[rule_type])++;
	
	rule->rule_type = rule_type;
	rule->idx = rt;
	
	return rule;

skip_avtab_rule:                
	while ((id = queue_remove(id_queue))) 
		free(id);
	while ((id = queue_remove(id_queue))) 
		free(id);
	while ((id = queue_remove(id_queue))) 
		free(id);
	while ((id = queue_remove(id_queue))) 
		free(id);
	return &dummy_rule_desc; /* 0 (i.e., NULL) is fail */
}


static int define_initial_sid(void)
{
	char *id = 0;
	int idx;
	
	if (pass == 2 ||(pass == 1 && !(parse_policy->opts & POLOPT_INITIAL_SIDS))) {
		id = queue_remove(id_queue);
		free(id);
		return 0;
	}
	
	/* add initial SID name; context will be added in define_initial_sid_context() */
	id = (char *) queue_remove(id_queue);
	if (!id) {
		yyerror("no name for SID definition?");
		free(id);
		return -1;
	}
	if(!is_valid_str_sz(id)) {
		sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
		yyerror(errormsg);
		free(id);
		return -1;
	}
	idx = add_initial_sid(id, parse_policy);
	if(idx == -2) {
		sprintf(errormsg, "duplicate initial SID decalaration (%s)\n", id);
		yyerror(errormsg);
		return -1;
	}
	else if(idx < 0)
		return -1;
			
	return 0;
}

/* If dontsave, then just clear the queue and return NULL (the return
 * should be ignored in this case).  Otherwise, allocate a context
 * structure and return it, or NULL for error
 */
static security_context_t *parse_security_context(int dontsave)
{
	char *id;
	user_item_t *user;
	int rt; 
	security_context_t *scontext;
	
	if (pass == 1 || dontsave) {
		id = queue_remove(id_queue);  /* user  */
		free(id);
		id = queue_remove(id_queue);  /* role  */
		free(id);
		id = queue_remove(id_queue);  /* type  */
		free(id);
#ifdef CONFIG_SECURITY_SELINUX_MLS
		{
		int l;
		id = queue_remove(id_queue); free(id); 
		for (l = 0; l < 2; l++) {
			while ((id = queue_remove(id_queue))) {
				free(id);
			}
		}
		}
#endif 
	return NULL; /* In this case this is not an error */
	}
	
	scontext = (security_context_t *)malloc(sizeof(security_context_t));
	if(scontext == NULL) {
		yyerror("out of memory");
		return NULL;
	}
	/* user */
	id = queue_remove(id_queue);
	if (!id) {
		yyerror("Security context missing user?");
		free(scontext);
		return NULL;
	}
	rt = get_user_by_name(id, &user, parse_policy);
	if(rt != 0) {
		sprintf(errormsg, "User %s is not defined in policy.", id);
		yyerror(errormsg);
		free(id);
		free(scontext);
		return NULL;
	}
	free(id);
	scontext->user = user;
	
	/* role */
	id = queue_remove(id_queue);
	if (!id) {
		yyerror("Security context missing role?");
		free(scontext);
		return NULL;
	}			
	rt = get_role_idx(id, parse_policy);
	if(rt < 0) {
		sprintf(errormsg, "Role %s is not defined in policy.", id);
		yyerror(errormsg);
		free(id);
		free(scontext);
		return NULL;
	}
	free(id);
	scontext->role = rt;
	
	/* type */
	id = queue_remove(id_queue);
	if (!id) {
		yyerror("Security context missing type?");
		free(scontext);
		return NULL;
	}			
	rt = get_type_idx(id, parse_policy);
	if(rt < 0) {
		sprintf(errormsg, "Type %s is not defined in policy.", id);
		yyerror(errormsg);
		free(id);
		free(scontext);
		return NULL;
	}
	free(id);
	scontext->type = rt;	
	
#ifdef CONFIG_SECURITY_SELINUX_MLS
	{
	int l;
	id = queue_remove(id_queue); free(id); 
	for (l = 0; l < 2; l++) {
		while ((id = queue_remove(id_queue))) {
			free(id);
		}
	}
	}
#endif 	
	return scontext;
}


static int define_initial_sid_context(void)
{
	char *id;
	int idx;
	security_context_t *scontext;

	if (pass == 1 || (pass == 2 && !(parse_policy->opts & POLOPT_INITIAL_SIDS))){
		id = (char *) queue_remove(id_queue); 
		parse_security_context(1);
		free(id);
		return 0;
	}

	id = (char *) queue_remove(id_queue);
	if (!id) {
		yyerror("no sid name for SID context definition?");
		return -1;
	}
	if(!is_valid_str_sz(id)) {
		sprintf(errormsg, "string \"%s\" exceeds APOL_SZ_SIZE", id);
		yyerror(errormsg);
		free(id);
		return -1;
	}
	idx = get_initial_sid_idx(id, parse_policy);
	if(idx < 0) {
		sprintf(errormsg, "%s is not a valid initial SID name", id);
		yyerror(errormsg);
		free(id);
		return -1;
	}
	free(id);
	scontext = parse_security_context(0);
	if(scontext == NULL) 
		return -1;
	if(add_initial_sid_context(idx, scontext, parse_policy) != 0) {
		yyerror("problem adding security context to Initial SID");
		return -1;
	}		
	
	return 0;
}

/************************************************************************
 *
 * Until we decide to include these additional statments in the analysis
 * policy database, all we do is free the various ids.  
 *
 ************************************************************************/



static int define_sens(void)
{
#ifdef CONFIG_SECURITY_SELINUX_MLS
	char *id;
	while ((id = queue_remove(id_queue))) 
		free(id);
	return 0;
#else
	yyerror("sensitivity definition in non-MLS configuration");
	return -1;
#endif
}

static int define_dominance(void)
{
#ifdef CONFIG_SECURITY_SELINUX_MLS
	char *id;
	while ((id = queue_remove(id_queue))) 
		free(id);
	return 0;
#else
	yyerror("dominance definition in non-MLS configuration");
	return -1;
#endif
}

static int define_category(void)
{
#ifdef CONFIG_SECURITY_SELINUX_MLS
	char *id;
	while ((id = queue_remove(id_queue))) 
		free(id);
	return 0;
#else
	yyerror("category definition in non-MLS configuration");
	return -1;
#endif
}

static int define_level(void)
{
#ifdef CONFIG_SECURITY_SELINUX_MLS
	char *id;
	while ((id = queue_remove(id_queue))) 
		free(id);
	return 0;
#else
	yyerror("level definition in non-MLS configuration");
	return -1;
#endif
}

static int define_common_base(void)
{
#ifdef CONFIG_SECURITY_SELINUX_MLS
	char *id;
	id = queue_remove(id_queue); free(id);
	while ((id = queue_remove(id_queue))) {
		free(id);
		while ((id = queue_remove(id_queue))) {
			free(id);
		}
	}
	return 0;
#else
	yyerror("MLS base permission definition in non-MLS configuration");
	return -1;
#endif
}


/* #ifdef CONFIG_SECURITY_SELINUX_MLS*/
#if 0
static int common_base_set(hashtab_key_t key, hashtab_datum_t datum, void *p)
{
	return 0;
}
#endif

static int define_av_base(void)
{
#ifdef CONFIG_SECURITY_SELINUX_MLS
	char *id;
	id = queue_remove(id_queue); free(id);
	while ((id = queue_remove(id_queue))) {
		free(id);
		while ((id = queue_remove(id_queue))) {
			free(id);
		}
	}
	return 0;
#else
	yyerror("MLS base permission definition in non-MLS configuration");
	return -1;
#endif
}




static int define_constraint(void)
{
	char *id;
	while ((id = queue_remove(id_queue))) 
		free(id);
	while ((id = queue_remove(id_queue))) 
		free(id);
	return 0;
}


static constraint_expr_t *
 define_cexpr(__u32 expr_type, __u32 arg1, __u32 arg2)
{
	char *id;
	if (expr_type == CEXPR_NAMES) {
		while ((id = queue_remove(id_queue))) 
			free(id);
	}
	return (constraint_expr_t *)1; /* any non-NULL value */
}




static int define_fs_context(int ver)
{
	int rt;
	
	rt = set_policy_version(ver, parse_policy);
	if(rt != 0) {
		yyerror("error setting policy version");
		return -1;
	}
	parse_security_context(1);
	parse_security_context(1);
	return 0;
}

static int define_port_context(int ver)
{
	char *id;

	int rt;
	
	rt = set_policy_version(ver, parse_policy);
	if(rt != 0) {
		yyerror("error setting policy version");
		return -1;
	}
	id = (char *) queue_remove(id_queue); 
	free(id);
	parse_security_context(1);
	return 0;
}

static int define_netif_context(int ver)
{
	int rt;
	
	rt = set_policy_version(ver, parse_policy);
	if(rt != 0) {
		yyerror("error setting policy version");
		return -1;
	}
	free(queue_remove(id_queue));
	parse_security_context(1);
	parse_security_context(1);
	return 0;
}

static int define_node_context(int ver)
{
	int rt;
	
	rt = set_policy_version(ver, parse_policy);
	if(rt != 0) {
		yyerror("error setting policy version");
		return -1;
	}
	parse_security_context(1);
	return 0;
}

/* removed Jul 2002 */

static int define_devfs_context(int has_type)
{
	int rt;
	
	rt = set_policy_version(POL_VER_PREJUL2002, parse_policy);
	if(rt != 0) {
		yyerror("error setting policy version");
		return -1;
	}
	free(queue_remove(id_queue));
	if (has_type)
		free(queue_remove(id_queue));
	parse_security_context(1);
	return 0;
}
/* removed Jul 2002 */

static int define_nfs_context(void)
{
	int rt;
	
	rt = set_policy_version(POL_VER_PREJUL2002, parse_policy);
	if(rt != 0) {
		yyerror("error setting policy version");
		return -1;
	}
	parse_security_context(1);
	return 0;
}

/* added Jul 2002 */
/* changed Jul 2003; added FSUSEXATTR */
static int define_fs_use(int behavior, int ver)
{
	int rt;
	
	rt = set_policy_version(ver, parse_policy);
	if(rt != 0) {
		yyerror("error setting policy version)");
		return -1;
	}
	free(queue_remove(id_queue));
	if(behavior != 0)
		parse_security_context(1);
	return 0;

}

/* added Jul 2002 */
static int define_genfs_context_helper(char *fstype, int has_type)
{
	int rt;
	
	rt = set_policy_version(POL_VER_JUL2002, parse_policy);
	if(rt != 0) {
		yyerror("error setting policy version");
		return -1;
	}
		free(fstype);
	free(queue_remove(id_queue));
	if (has_type)
		free(queue_remove(id_queue));
	parse_security_context(1);
	return 0;
}

/* added Jul 2002 */
static int define_genfs_context(int has_type)
{
	return define_genfs_context_helper(queue_remove(id_queue), has_type);
}
