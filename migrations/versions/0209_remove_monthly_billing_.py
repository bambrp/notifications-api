"""

Revision ID: 0209_remove_monthly_billing
Revises: 84c3b6eb16b3
Create Date: 2018-07-27 14:46:30.109811

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0209_remove_monthly_billing'
down_revision = '84c3b6eb16b3'


def upgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    op.drop_index('ix_monthly_billing_service_id', table_name='monthly_billing')
    op.drop_table('monthly_billing')
    # ### end Alembic commands ###


def downgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    op.create_table('monthly_billing',
    sa.Column('id', postgresql.UUID(), autoincrement=False, nullable=False),
    sa.Column('service_id', postgresql.UUID(), autoincrement=False, nullable=False),
    sa.Column('notification_type', postgresql.ENUM('email', 'sms', 'letter', name='notification_type'), autoincrement=False, nullable=False),
    sa.Column('monthly_totals', postgresql.JSON(astext_type=sa.Text()), autoincrement=False, nullable=False),
    sa.Column('updated_at', postgresql.TIMESTAMP(), autoincrement=False, nullable=False),
    sa.Column('start_date', postgresql.TIMESTAMP(), autoincrement=False, nullable=False),
    sa.Column('end_date', postgresql.TIMESTAMP(), autoincrement=False, nullable=False),
    sa.ForeignKeyConstraint(['service_id'], ['services.id'], name='monthly_billing_service_id_fkey'),
    sa.PrimaryKeyConstraint('id', name='monthly_billing_pkey'),
    sa.UniqueConstraint('service_id', 'start_date', 'notification_type', name='uix_monthly_billing')
    )
    op.create_index('ix_monthly_billing_service_id', 'monthly_billing', ['service_id'], unique=False)
    # ### end Alembic commands ###
